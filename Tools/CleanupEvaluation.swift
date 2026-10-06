import Darwin
import Foundation

/// Compiles with the production cleanup files; never opens the microphone or pasteboard.
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

    @MainActor
    static func main() async throws {
        let arguments = CommandLine.arguments
        guard arguments.count >= 2 else {
            FileHandle.standardError.write(Data("Usage: cleanup-eval corpus.jsonl [--baseline] [--patient]\n".utf8))
            return
        }
        let corpus = try String(contentsOfFile: arguments[1], encoding: .utf8)
            .split(separator: "\n").map { try JSONDecoder().decode(Example.self, from: Data($0.utf8)) }
        let backend = CleanupBackendFactory.make()
        let budget: UInt64 = arguments.contains("--patient") ? 30_000_000_000 : 2_000_000_000
        let cleanup = TranscriptCleanup(backend: backend, timeoutNanoseconds: budget)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        for round in 1...2 {
            for example in corpus {
                let started = ProcessInfo.processInfo.systemUptime
                let result = arguments.contains("--baseline")
                    ? TranscriptCleanupResult.raw(example.raw)
                    : try await cleanup.clean(example.raw)
                var usage = rusage()
                getrusage(RUSAGE_SELF, &usage)
                let measurement = Measurement(id: example.id, round: round, raw: example.raw,
                                              expected: example.expected, delivered: result.text,
                                              outcome: result.outcome.rawValue,
                                              milliseconds: (ProcessInfo.processInfo.systemUptime - started) * 1000,
                                              peakResidentBytes: Int(usage.ru_maxrss), exactMatch: result.text == example.expected,
                                              missingProtectedText: example.preserve.filter { !result.text.contains($0) })
                FileHandle.standardOutput.write(try encoder.encode(measurement) + Data([0x0A]))
                // Independent examples measure generation, rather than the previous timeout's busy fallback.
                await cleanup.shutDown()
            }
        }
    }
}
