import Darwin
import Foundation

/// Runs the production cleanup code over a JSONL corpus with the on-device model.
/// Needs Apple Intelligence; never opens the microphone, pasteboard, or history.
@main
struct CleanupEvaluation {
    struct Example: Decodable {
        let id: String
        let raw: String
        let expected: String
        let preserve: [String]
    }

    struct Measurement: Encodable {
        let id: String
        let round: Int
        let raw: String
        let expected: String
        let delivered: String
        let outcome: String
        let milliseconds: Double
        let peakResidentBytes: Int
        let exactMatch: Bool
        let missingProtectedText: [String]
    }

    static let usage = """
        Usage: cleanup-eval corpus.jsonl [--profile dictation|selection] [--prompt file] [--patient] [--baseline]
          --patient   allow 30 s per example instead of the profile's deadline
          --baseline  deliver the raw text, for comparison

        """

    @MainActor
    static func main() async throws {
        let arguments = Array(CommandLine.arguments.dropFirst())
        guard let corpusPath = arguments.first, !corpusPath.hasPrefix("--") else {
            FileHandle.standardError.write(Data(usage.utf8))
            exit(2)
        }
        func value(after flag: String) -> String? {
            arguments.firstIndex(of: flag).flatMap { arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil }
        }
        var profile = value(after: "--profile") == "selection" ? CleanupProfile.selection : .dictation
        if arguments.contains("--patient") { profile.timeout = 30 }
        let instructions = try value(after: "--prompt").map { try String(contentsOfFile: $0, encoding: .utf8) }
            ?? CleanupPrompt.standard
        let baseline = arguments.contains("--baseline")

        let corpus = try String(contentsOfFile: corpusPath, encoding: .utf8)
            .split(separator: "\n").map { try JSONDecoder().decode(Example.self, from: Data($0.utf8)) }
        let backend = CleanupBackendFactory.make()
        if !baseline && !backend.isAvailable {
            FileHandle.standardError.write(Data("The on-device model is unavailable on this Mac.\n".utf8))
            exit(1)
        }
        let cleanup = TextCleanup(backend: backend)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        var measurements: [Measurement] = []

        for round in 1...2 {
            for example in corpus {
                let started = ProcessInfo.processInfo.systemUptime
                let result = baseline
                    ? CleanupResult.original(example.raw, .unchanged)
                    : try await cleanup.clean(example.raw, instructions: instructions, profile: profile)
                var usage = rusage()
                getrusage(RUSAGE_SELF, &usage)
                let measurement = Measurement(
                    id: example.id, round: round, raw: example.raw, expected: example.expected,
                    delivered: result.text, outcome: result.outcome.rawValue,
                    milliseconds: (ProcessInfo.processInfo.systemUptime - started) * 1000,
                    peakResidentBytes: Int(usage.ru_maxrss), exactMatch: result.text == example.expected,
                    missingProtectedText: example.preserve.filter { !result.text.contains($0) })
                measurements.append(measurement)
                FileHandle.standardOutput.write(try encoder.encode(measurement) + Data([0x0A]))
                // Measure each example on its own, not the previous timeout's busy fallback.
                await cleanup.shutDown()
            }
        }

        let outcomes = Dictionary(grouping: measurements, by: \.outcome).mapValues(\.count)
            .sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }.joined(separator: ", ")
        let times = measurements.map(\.milliseconds).sorted()
        let summary = """
            \(measurements.filter(\.exactMatch).count)/\(measurements.count) reference matches; \
            \(measurements.filter { !$0.missingProtectedText.isEmpty }.count) with missing protected text
            outcomes: \(outcomes)
            median \(Int(times[times.count / 2])) ms, max \(Int(times.last ?? 0)) ms

            """
        FileHandle.standardError.write(Data(summary.utf8))
    }
}
