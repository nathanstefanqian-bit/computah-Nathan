import ComputahCore
import Foundation

final class DeepgramSpeechSession: SpeechProviderSession {
    let request: URLRequest
    var usage: SpeechUsage? { nil }
    private var turns = SpeechTurnIdentity()

    init(endpoint: URL, key: String) {
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "model", value: "flux-general-en"),
            URLQueryItem(name: "encoding", value: "linear16"),
            URLQueryItem(name: "sample_rate", value: "16000"),
            URLQueryItem(name: "eager_eot_threshold", value: "0.5"),
            URLQueryItem(name: "eot_threshold", value: "0.7"),
        ]
        var request = URLRequest(url: components.url!)
        request.setValue("Token \(key)", forHTTPHeaderField: "Authorization")
        self.request = request
    }

    func openingMessages() throws -> [URLSessionWebSocketTask.Message] { [] }
    func audioMessages(_ pcm: Data) throws -> [URLSessionWebSocketTask.Message] { [.data(pcm)] }
    func closingMessages() throws -> [URLSessionWebSocketTask.Message] { [] }

    func consume(_ message: URLSessionWebSocketTask.Message) throws -> [SpeechSessionEvent] {
        guard case .string(let text) = message, let data = text.data(using: .utf8),
              let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { throw SpeechSessionError.unexpectedMessage }
        var events: [SpeechSessionEvent] = [.provider(payload)]
        if payload["type"] as? String == "Error" {
            throw SpeechSessionError.providerRejected("Deepgram rejected the speech stream.")
        }
        guard payload["type"] as? String == "TurnInfo",
              let turnIndex = payload["turn_index"] as? Int,
              let turnID = turns.accept(sequence: payload["sequence_id"] as? Int, turn: turnIndex)
        else { return events }
        let transcript = payload["transcript"] as? String ?? ""
        let event = payload["event"] as? String
        if event == "StartOfTurn" { events.append(.turnBegan(turnID)) }
        if event == "TurnResumed" { events.append(.resumed) }
        let final = event == "EndOfTurn"
        if !transcript.isEmpty { events.append(.text(transcript, final: final, turnID: turnID)) }
        if event == "EagerEndOfTurn", !transcript.isEmpty {
            events.append(.eager(transcript, turnID: turnID))
        }
        return events
    }
}
