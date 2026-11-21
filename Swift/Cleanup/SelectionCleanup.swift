import Foundation

/// Cleans selected text with the user's instructions. Reading the selection and
/// delivering the result belong to the action coordinator.
@MainActor
final class SelectionCleanup {
    private let cleanup: TextCleanup
    private let instructions: () -> String

    init(cleanup: TextCleanup, instructions: @escaping () -> String) {
        self.cleanup = cleanup
        self.instructions = instructions
    }

    var isAvailable: Bool { cleanup.isAvailable }

    func clean(_ text: String) async throws -> CleanupResult {
        try await cleanup.clean(text, instructions: instructions(), profile: .selection)
    }
}
