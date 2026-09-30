import ComputahSpeech
import Foundation

struct SpeechUsage {
    let provider: SpeechProvider
    let audioSeconds: Double
    let estimatedCostCNY: Double
    let providerReportedDuration: Bool
}

enum SpeechSessionEvent {
    case provider([String: Any])
    case turnBegan(String)
    case text(String, final: Bool, turnID: String)
    case eager(String, turnID: String)
    case resumed
}

protocol SpeechProviderSession: AnyObject {
    var request: URLRequest { get }
    var usage: SpeechUsage? { get }
    func openingMessages() throws -> [URLSessionWebSocketTask.Message]
    func audioMessages(_ pcm: Data) throws -> [URLSessionWebSocketTask.Message]
    func closingMessages() throws -> [URLSessionWebSocketTask.Message]
    func consume(_ message: URLSessionWebSocketTask.Message) throws -> [SpeechSessionEvent]
}

enum SpeechSessionFactory {
    static func make(configuration: SpeechProviderConfiguration, key: String) -> SpeechProviderSession {
        switch configuration.provider {
        case .deepgram:
            return DeepgramSpeechSession(endpoint: configuration.endpoint, key: key)
        case .volcengine:
            return VolcengineSpeechSession(
                endpoint: configuration.endpoint, key: key,
                resourceID: configuration.resourceID ?? "volc.seedasr.sauc.duration")
        }
    }
}

enum SpeechSessionError: LocalizedError {
    case unexpectedMessage
    case providerRejected(String)
    case malformedResponse
    case outOfOrderResponse

    var errorDescription: String? {
        switch self {
        case .unexpectedMessage: return "The speech provider returned an unexpected WebSocket message."
        case .providerRejected(let message): return message
        case .malformedResponse: return "The speech provider returned a malformed response."
        case .outOfOrderResponse: return "The speech provider returned an out-of-order response."
        }
    }
}
