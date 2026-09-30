import Foundation

public enum SpeechProvider: String, Codable, Sendable {
    case deepgram
    case volcengine

    public var recognitionLabel: String {
        switch self {
        case .deepgram: return "Deepgram Speech Recognition"
        case .volcengine: return "Volcengine Speech Recognition"
        }
    }
}

public enum SpeechDiagnosticLimit {
    public static let maximumSeconds = 30
    public static let pcmBytesPerSecond = 16_000 * 2
    public static let maximumPCMBytes = maximumSeconds * pcmBytesPerSecond
}

public struct SpeechProviderConfiguration: Equatable, Sendable {
    public let provider: SpeechProvider
    public let endpoint: URL
    public let credentialName: String
    public let resourceID: String?

    public static let deepgram = SpeechProviderConfiguration(
        provider: .deepgram,
        endpoint: URL(string: "wss://api.deepgram.com/v2/listen")!,
        credentialName: "DEEPGRAM_API_KEY",
        resourceID: nil)

    public static func volcengine(resourceID: String = "volc.seedasr.sauc.duration")
        -> SpeechProviderConfiguration
    {
        SpeechProviderConfiguration(
            provider: .volcengine,
            endpoint: URL(string: "wss://openspeech.bytedance.com/api/v3/sauc/bigmodel_async")!,
            credentialName: "VOLCENGINE_SPEECH_API_KEY",
            resourceID: resourceID)
    }

    public static func resolve(_ value: String?, resourceID: String? = nil) throws
        -> SpeechProviderConfiguration
    {
        let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch normalized {
        case nil, "", "deepgram":
            return .deepgram
        case "volcengine":
            let resource = resourceID?.trimmingCharacters(in: .whitespacesAndNewlines)
            return .volcengine(resourceID: resource?.isEmpty == false ? resource! : "volc.seedasr.sauc.duration")
        default:
            throw SpeechConfigurationError.unsupportedProvider(value ?? "")
        }
    }
}

public enum SpeechConfigurationError: LocalizedError {
    case unsupportedProvider(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedProvider(let value):
            return "Unsupported SPEECH_PROVIDER '\(value)'. Use deepgram or volcengine."
        }
    }
}
