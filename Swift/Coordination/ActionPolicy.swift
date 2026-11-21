import Foundation

/// Who wins when two actions want the same resources. A lower priority never
/// preempts a higher one.
enum ActionPriority: Int, Comparable, CaseIterable {
    case tts, instruct, stt

    /// Highest first: dictation, then instructions, then read-aloud.
    static let order: [ActionPriority] = allCases.sorted(by: >)

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

enum ActionRequest: Equatable {
    case toggleRecord
    case instruct
    case readAloud

    var priority: ActionPriority {
        switch self {
        case .toggleRecord: return .stt
        case .instruct: return .instruct
        case .readAloud: return .tts
        }
    }
}

enum InstructStage: Equatable {
    case reading, cleaning, inserting
}

/// What the foreground action is doing. `run` identifies the owning task; `target`
/// is the frontmost app's pid when the result will be delivered.
enum ActionState: Equatable {
    case idle
    case capturing
    case transcribing(run: Int, target: pid_t?)
    case cleaning(run: Int, target: pid_t?)
    case inserting(run: Int, target: pid_t?)
    case readingSelection(run: Int)
    case speaking(run: Int)
    case instructing(run: Int, stage: InstructStage, target: pid_t?)

    var priority: ActionPriority? {
        switch self {
        case .idle: return nil
        case .capturing, .transcribing, .cleaning, .inserting: return .stt
        case .instructing: return .instruct
        case .readingSelection, .speaking: return .tts
        }
    }

    var run: Int? {
        switch self {
        case .idle, .capturing: return nil
        case .transcribing(let run, _), .cleaning(let run, _), .inserting(let run, _),
             .readingSelection(let run), .speaking(let run), .instructing(let run, _, _):
            return run
        }
    }
}

/// What the menu-bar icon shows. Derived from state, never set by features.
enum StatusPhase: Equatable {
    case ready, recording, processing, transforming, speaking
}

extension ActionState {
    /// Reads take well under a second, so they keep the ready icon.
    var phase: StatusPhase {
        switch self {
        case .idle, .readingSelection: return .ready
        case .capturing: return .recording
        case .transcribing: return .processing
        case .cleaning, .inserting: return .transforming
        case .instructing(_, let stage, _): return stage == .reading ? .ready : .transforming
        case .speaking: return .speaking
        }
    }
}

enum Rejection: Equatable {
    case recording, busy
}

enum ActionDecision: Equatable {
    /// Start the request. While recording, a record request stops the capture.
    case accept
    /// Wind down the foreground action, then start the request.
    case replace
    /// Wind down the foreground action and start nothing, like a toggle off.
    case cancel
    case reject(Rejection)
}

enum ActionPolicy {
    /// Derived from priority: a higher request replaces, a lower one is rejected, and
    /// equals follow their own feature's rule.
    static func decide(_ state: ActionState, _ request: ActionRequest) -> ActionDecision {
        guard let held = state.priority else { return .accept }
        let asked = request.priority
        if asked > held {
            // The paste is already on its way; the run finishes in the background.
            if case .instructing(_, .inserting, _) = state { return .accept }
            return .replace
        }
        if asked < held {
            if case .capturing = state { return .reject(.recording) }
            return .reject(.busy)
        }
        switch (state, request) {
        case (.capturing, _), (.transcribing, _), (.inserting, _): return .accept
        case (.cleaning, _): return .replace
        case (_, .readAloud): return .cancel
        default: return .reject(.busy)
        }
    }
}
