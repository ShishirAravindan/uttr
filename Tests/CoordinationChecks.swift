import Foundation

/// The action policy table. No audio, models, clipboard, or permissions.
@main
struct CoordinationChecks {
    static func main() {
        checkPriorityOrder()
        checkTable()
        print("Coordination checks passed")
    }

    static func checkPriorityOrder() {
        precondition(ActionPriority.order == [.stt, .instruct, .tts])
        precondition(ActionRequest.toggleRecord.priority > ActionRequest.instruct.priority)
        precondition(ActionRequest.instruct.priority > ActionRequest.readAloud.priority)
    }

    static func checkTable() {
        let states: [(String, ActionState)] = [
            ("idle", .idle),
            ("capturing", .capturing),
            ("transcribing", .transcribing(run: 1, target: 10)),
            ("cleaning", .cleaning(run: 1, target: 10)),
            ("inserting", .inserting(run: 1, target: 10)),
            ("readingSelection", .readingSelection(run: 1)),
            ("speaking", .speaking(run: 1)),
            ("instructing.reading", .instructing(run: 1, stage: .reading, target: 10)),
            ("instructing.cleaning", .instructing(run: 1, stage: .cleaning, target: 10)),
            ("instructing.inserting", .instructing(run: 1, stage: .inserting, target: 10)),
        ]
        // Columns: record, instruct, readAloud.
        let expected: [String: [ActionDecision]] = [
            "idle": [.accept, .accept, .accept],
            "capturing": [.accept, .reject(.recording), .reject(.recording)],
            "transcribing": [.accept, .reject(.busy), .reject(.busy)],
            "cleaning": [.replace, .reject(.busy), .reject(.busy)],
            "inserting": [.accept, .reject(.busy), .reject(.busy)],
            "readingSelection": [.replace, .replace, .cancel],
            "speaking": [.replace, .replace, .cancel],
            "instructing.reading": [.replace, .reject(.busy), .reject(.busy)],
            "instructing.cleaning": [.replace, .reject(.busy), .reject(.busy)],
            "instructing.inserting": [.accept, .reject(.busy), .reject(.busy)],
        ]
        let requests: [ActionRequest] = [.toggleRecord, .instruct, .readAloud]
        for (name, state) in states {
            let row = expected[name]!
            for (request, want) in zip(requests, row) {
                let got = ActionPolicy.decide(state, request)
                precondition(got == want, "\(name) x \(request): \(got), expected \(want)")
            }
        }

        // Lower priority never preempts higher.
        for (name, state) in states {
            guard let held = state.priority else { continue }
            for request in requests where request.priority < held {
                guard case .reject = ActionPolicy.decide(state, request) else {
                    preconditionFailure("\(request) must not preempt \(name)")
                }
            }
        }
    }
}
