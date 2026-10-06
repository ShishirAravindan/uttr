import Foundation

enum CleanupOutcome: String, Codable {
    case cleaned, unchanged, unavailable, unsupportedLanguage, timedOut, failed, invalidOutput, busy, tooLong
}

struct TranscriptCleanupResult {
    let rawText: String
    let text: String
    let outcome: CleanupOutcome

    static func raw(_ text: String, reason: CleanupOutcome = .unchanged) -> Self {
        Self(rawText: text, text: text, outcome: reason)
    }
}

@MainActor
protocol CleanupGenerating: AnyObject {
    var isAvailable: Bool { get }
    func supports(_ text: String) -> Bool
    func generate(_ text: String) async throws -> String
}

extension CleanupGenerating {
    func supports(_ text: String) -> Bool { true }
}

@MainActor
protocol TranscriptCleaning: AnyObject {
    func clean(_ text: String) async throws -> TranscriptCleanupResult
    func shutDown() async
}

/// A deadline bounds delivery, even when the model ignores cancellation. The
/// outstanding generation stays owned; another utterance uses raw text until it ends.
@MainActor
final class TranscriptCleanup: TranscriptCleaning {
    private let backend: CleanupGenerating
    private let timeoutNanoseconds: UInt64
    private let waitForDeadline: (UInt64) async throws -> Void
    private var generation: Task<Void, Never>?

    init(backend: CleanupGenerating, timeoutNanoseconds: UInt64 = 2_000_000_000,
         waitForDeadline: @escaping (UInt64) async throws -> Void = { try await Task.sleep(nanoseconds: $0) }) {
        self.backend = backend
        self.timeoutNanoseconds = timeoutNanoseconds
        self.waitForDeadline = waitForDeadline
    }

    func clean(_ text: String) async throws -> TranscriptCleanupResult {
        let started = ProcessInfo.processInfo.systemUptime
        try Task.checkCancellation()
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return .raw(text) }
        // Short utterances are the MVP's target. Long input can exceed the system model's context.
        guard text.count <= 4000 else { return .raw(text, reason: .tooLong) }
        guard backend.isAvailable else { return .raw(text, reason: .unavailable) }
        guard backend.supports(text) else { return .raw(text, reason: .unsupportedLanguage) }
        guard generation == nil else { return .raw(text, reason: .busy) }

        let request = CleanupRequest()
        let backend = self.backend
        let timeoutNanoseconds = self.timeoutNanoseconds
        let task = Task { [weak self] in
            do {
                let candidate = try await backend.generate(text).trimmingCharacters(in: .whitespacesAndNewlines)
                // Shape checks are not a semantic verifier; fidelity is evaluated with the corpus.
                let valid = CleanupOutput.accepts(candidate, for: text)
                var result = valid
                    ? TranscriptCleanupResult(rawText: text, text: candidate, outcome: candidate == text ? .unchanged : .cleaned)
                    : .raw(text, reason: .invalidOutput)
                // Actor scheduling may delay the timer. Late generation still loses.
                if (ProcessInfo.processInfo.systemUptime - started) * 1_000_000_000 >= Double(timeoutNanoseconds) {
                    result = .raw(text, reason: .timedOut)
                }
                request.finish(.success(result))
            } catch {
                request.finish(.success(.raw(text, reason: .failed)))
            }
            self?.generation = nil
        }
        generation = task
        let waitForDeadline = self.waitForDeadline

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                request.continuation = continuation
                request.deadline = Task {
                    let elapsed = (ProcessInfo.processInfo.systemUptime - started) * 1_000_000_000
                    let remaining = UInt64(max(0, Double(timeoutNanoseconds) - elapsed))
                    do { try await waitForDeadline(remaining) } catch { return }
                    request.finish(.success(.raw(text, reason: .timedOut)))
                    task.cancel()
                }
            }
        } onCancel: {
            Task { @MainActor in
                request.finish(.failure(CancellationError()))
                task.cancel()
            }
        }
    }

    func shutDown() async {
        generation?.cancel()
        await generation?.value
    }
}

/// Conservative checks for errors observed in evaluation, not proof of meaning.
enum CleanupOutput {
    static func accepts(_ output: String, for input: String) -> Bool {
        guard !output.isEmpty, output.count <= max(80, input.count * 2) else { return false }
        if input.contains("?"), !output.contains("?") { return false }
        // Literal numeric edits and lost negation are too costly to guess at in this MVP.
        let numberPattern = #"\d+(?:[.,]\d+)*"#
        if matches(numberPattern, in: input).sorted() != matches(numberPattern, in: output).sorted() { return false }
        let normalizedInput = input.lowercased().replacingOccurrences(of: "’", with: "'")
        let normalizedOutput = output.lowercased().replacingOccurrences(of: "’", with: "'")
        let negationPattern = #"\b(?:not|never|cannot|without|don't|doesn't|can't|won't|isn't|aren't|wasn't|weren't|shouldn't|wouldn't|couldn't|mustn't)\b"#
        for word in matches(negationPattern, in: normalizedInput) {
            if !normalizedOutput.contains(word) { return false }
        }
        // Never erase a script present in the original, including mixed-language speech.
        for script in ["Devanagari", "Tamil", "Bengali", "Arabic", "Hebrew", "Han", "Hiragana", "Katakana", "Hangul", "Cyrillic", "Greek", "Thai"] {
            let pattern = "\\p{script=\(script)}"
            if input.range(of: pattern, options: .regularExpression) != nil,
               output.range(of: pattern, options: .regularExpression) == nil { return false }
        }
        // These repetitions carry emphasis, rather than being duplicate sentence starts.
        for phrase in ["very very", "really really", "so so", "never never"] {
            if input.localizedCaseInsensitiveContains(phrase), !output.localizedCaseInsensitiveContains(phrase) { return false }
        }
        // Protect literal identifiers, paths, URLs, and version strings when present.
        let pattern = #"https?://[^\s]+|(?:~?/)[^\s,;]+|\b\w+_\w+\b|\b[a-z]+[A-Z]\w*\b|\b\d+\.\d+(?:\.\d+)*\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
        let range = NSRange(input.startIndex..., in: input)
        for match in regex.matches(in: input, range: range) {
            guard let range = Range(match.range, in: input) else { continue }
            let literal = String(input[range]).trimmingCharacters(in: CharacterSet(charactersIn: ".!?"))
            if !output.contains(literal) { return false }
        }
        return true
    }

    private static func matches(_ pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap {
            Range($0.range, in: text).map { String(text[$0]) }
        }
    }
}

@MainActor
private final class CleanupRequest {
    var continuation: CheckedContinuation<TranscriptCleanupResult, Error>?
    var deadline: Task<Void, Never>?
    private var finished = false

    func finish(_ result: Result<TranscriptCleanupResult, Error>) {
        guard !finished else { return }
        finished = true
        deadline?.cancel()
        continuation?.resume(with: result)
        continuation = nil
        deadline = nil
    }
}
