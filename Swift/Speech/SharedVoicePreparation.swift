import Foundation

/// One preparation can outlive any individual read that is waiting for it.
@MainActor
final class SharedVoicePreparation<Value> {
    private var work: Task<Void, Never>?
    private var result: Result<Value, Error>?
    private var waiters: [UUID: CheckedContinuation<Value, Error>] = [:]

    init(_ operation: @escaping @MainActor () async throws -> Value) {
        work = Task { [weak self] in
            do {
                let value = try await operation()
                self?.finish(.success(value))
            } catch {
                self?.finish(.failure(error))
            }
            self?.work = nil
        }
    }

    func value() async throws -> Value {
        let id = UUID()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            if let result { return try result.get() }
            return try await withCheckedThrowingContinuation { waiters[id] = $0 }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.waiters.removeValue(forKey: id)?.resume(throwing: CancellationError())
            }
        }
    }

    func cancel() {
        work?.cancel()
        finish(.failure(CancellationError()))
    }

    private func finish(_ outcome: Result<Value, Error>) {
        guard result == nil else { return }
        result = outcome
        let pending = waiters.values
        waiters.removeAll()
        for waiter in pending { waiter.resume(with: outcome) }
    }
}
