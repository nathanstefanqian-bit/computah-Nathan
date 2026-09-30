import Foundation

public struct VolcengineTranscript: Equatable {
    public let text: String
    public let final: Bool
    public let turnKey: String
    public let deduplicationKey: String
}

public struct VolcengineTranscriptResult: Equatable {
    public let transcripts: [VolcengineTranscript]
    public let audioMilliseconds: Double
    public let prefetch: Bool
}

public enum VolcenginePrefetchTransition: Equatable {
    case cancel
    case prepare(String)
}

public struct VolcenginePrefetchTracker {
    private var textByTurn: [String: String] = [:]

    public init() {}

    public mutating func transitions(
        turnID: String, text: String, final: Bool, prefetch: Bool
    ) -> [VolcenginePrefetchTransition] {
        if final {
            textByTurn.removeValue(forKey: turnID)
            return []
        }
        var result: [VolcenginePrefetchTransition] = []
        if let previous = textByTurn[turnID], previous != text {
            textByTurn.removeValue(forKey: turnID)
            result.append(.cancel)
        }
        if prefetch, textByTurn[turnID] != text {
            textByTurn[turnID] = text
            result.append(.prepare(text))
        }
        return result
    }
}

public enum VolcengineTranscriptDecoder {
    public static func decode(_ payload: [String: Any], finalFrame: Bool)
        -> VolcengineTranscriptResult
    {
        let result = payload["result"] as? [String: Any]
        let utterances = result?["utterances"] as? [[String: Any]] ?? []
        var transcripts: [VolcengineTranscript] = []
        if utterances.isEmpty {
            let text = (result?["text"] as? String ?? payload["text"] as? String ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                transcripts.append(VolcengineTranscript(
                    text: text, final: finalFrame, turnKey: "result",
                    deduplicationKey: "result:\(text)"))
            }
        } else {
            for utterance in utterances {
                let text = (utterance["text"] as? String ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { continue }
                let start = integer(utterance["start_time"]) ?? 0
                let end = integer(utterance["end_time"]) ?? 0
                transcripts.append(VolcengineTranscript(
                    text: text, final: boolean(utterance["definite"]) || finalFrame,
                    turnKey: String(start), deduplicationKey: "\(start):\(end):\(text)"))
            }
        }

        let audioInfo = payload["audio_info"] as? [String: Any]
            ?? result?["audio_info"] as? [String: Any]
        var milliseconds = double(audioInfo?["duration"])
            ?? double(result?["duration"])
            ?? double(payload["duration"])
            ?? 0
        milliseconds = max(
            milliseconds,
            utterances.compactMap { double($0["end_time"]) }.max() ?? 0)
        return VolcengineTranscriptResult(
            transcripts: transcripts, audioMilliseconds: milliseconds,
            prefetch: boolean(result?["prefetch"] ?? payload["prefetch"]))
    }

    private static func integer(_ value: Any?) -> Int? {
        if let number = value as? NSNumber { return number.intValue }
        if let string = value as? String { return Int(string) }
        return nil
    }

    private static func double(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let string = value as? String { return Double(string) }
        return nil
    }

    private static func boolean(_ value: Any?) -> Bool {
        if let number = value as? NSNumber { return number.boolValue }
        if let string = value as? String { return ["true", "1"].contains(string.lowercased()) }
        return false
    }
}
