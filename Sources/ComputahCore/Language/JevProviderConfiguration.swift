import Foundation

public struct JevProviderConfiguration: Equatable, Sendable {
    public let name: String
    public let endpoint: URL
    public let model: String
    public let credentialName: String

    public static let typeSafe = JevProviderConfiguration(
        name: "typesafe",
        endpoint: URL(string: "https://api.typesafe.ai/v1/systemone")!,
        model: "jev-1.13.0",
        credentialName: "TYPESAFE_API_KEY")

    public static let openRouter = JevProviderConfiguration(
        name: "openrouter",
        endpoint: URL(string: "https://openrouter.ai/api/alpha/decisions")!,
        model: "typesafe/jev-1.13",
        credentialName: "OPENROUTER_API_KEY")

    public static func resolve(_ rawValue: String?) throws -> Self {
        switch rawValue?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case nil, "", "typesafe":
            return .typeSafe
        case "openrouter":
            return .openRouter
        case let value?:
            throw JevFailure.invalid(
                "Unsupported JEV_PROVIDER '\(value)'. Use 'typesafe' or 'openrouter'.")
        }
    }
}
