import Foundation

/// Attempts are counted at the HTTP boundary. Missing provider usage stays unknown.
public struct ModelUsage: Codable, Equatable, Sendable {
    public var requests = 0
    public var reportedInputTokens = 0
    public var requestsWithoutTokenUsage = 0
    public var reportedCostUSD = 0.0
    public var requestsWithoutCost = 0
    public var inputTokens: Int? { requestsWithoutTokenUsage == 0 ? reportedInputTokens : nil }
    public var actualCostUSD: Double? { requestsWithoutCost == 0 ? reportedCostUSD : nil }
    public var estimatedCostUSD: Double? {
        inputTokens.map { Double($0) * JevCosts.inputUSDPerMillion / 1_000_000 }
    }

    public init(
        requests: Int = 0, reportedInputTokens: Int = 0, requestsWithoutTokenUsage: Int = 0,
        reportedCostUSD: Double = 0, requestsWithoutCost: Int = 0
    ) {
        self.requests = requests
        self.reportedInputTokens = reportedInputTokens
        self.requestsWithoutTokenUsage = requestsWithoutTokenUsage
        self.reportedCostUSD = reportedCostUSD
        self.requestsWithoutCost = requestsWithoutCost
    }

    func adding(_ other: ModelUsage) -> ModelUsage {
        ModelUsage(
            requests: requests + other.requests,
            reportedInputTokens: reportedInputTokens + other.reportedInputTokens,
            requestsWithoutTokenUsage: requestsWithoutTokenUsage + other.requestsWithoutTokenUsage,
            reportedCostUSD: reportedCostUSD + other.reportedCostUSD,
            requestsWithoutCost: requestsWithoutCost + other.requestsWithoutCost)
    }

    func since(_ earlier: ModelUsage) -> ModelUsage {
        ModelUsage(
            requests: requests - earlier.requests,
            reportedInputTokens: reportedInputTokens - earlier.reportedInputTokens,
            requestsWithoutTokenUsage: max(0, requestsWithoutTokenUsage - earlier.requestsWithoutTokenUsage),
            reportedCostUSD: reportedCostUSD - earlier.reportedCostUSD,
            requestsWithoutCost: max(0, requestsWithoutCost - earlier.requestsWithoutCost))
    }
}

final class ModelUsageTracker: @unchecked Sendable {
    private let lock = NSLock()
    private var usage = ModelUsage()
    var snapshot: ModelUsage {
        lock.lock()
        defer { lock.unlock() }
        return usage
    }
    func beginRequest() {
        lock.lock()
        defer { lock.unlock() }
        usage.requests += 1
        usage.requestsWithoutTokenUsage += 1
        usage.requestsWithoutCost += 1
    }
    func received(inputTokens: Int?, costUSD: Double?) {
        lock.lock()
        defer { lock.unlock() }
        if let inputTokens, inputTokens >= 0 {
            usage.reportedInputTokens += inputTokens
            usage.requestsWithoutTokenUsage -= 1
        }
        if let costUSD, costUSD.isFinite, costUSD >= 0 {
            usage.reportedCostUSD += costUSD
            usage.requestsWithoutCost -= 1
        }
    }
}
