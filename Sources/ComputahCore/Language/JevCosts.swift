import Foundation

/// Aggregate accounting only. Never retains commands, app content, or credentials.
public final class JevCosts: @unchecked Sendable {
    // Public list price, checked 2026-09-25: https://docs.typesafe.ai/models
    // Output tokens are free. This is an estimate, not account-specific billing.
    public static let pricedModel = "jev-1.13.0"
    public static let pricedModels = Set(["jev-1.13.0", "typesafe/jev-1.13"])
    public static let inputUSDPerMillion = 0.042

    public struct Total: Codable, Equatable, Sendable {
        public var enabled = false
        public var since = Date()
        public var requests = 0
        public var missingUsage = 0
        public var inputTokens = 0
        public var unpricedTokens = 0
        public var estimatedUSD = 0.0
        public var reportedUSD = 0.0
        public var estimatedRequests = 0
        public var missingCost = 0
        public var totalUSD: Double { reportedUSD + estimatedUSD }

        public init() {}

        private enum CodingKeys: String, CodingKey {
            case enabled, since, requests, missingUsage, inputTokens, unpricedTokens, estimatedUSD
            case reportedUSD, estimatedRequests, missingCost
        }

        public init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            enabled = try values.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
            since = try values.decodeIfPresent(Date.self, forKey: .since) ?? Date()
            requests = try values.decodeIfPresent(Int.self, forKey: .requests) ?? 0
            missingUsage = try values.decodeIfPresent(Int.self, forKey: .missingUsage) ?? 0
            inputTokens = try values.decodeIfPresent(Int.self, forKey: .inputTokens) ?? 0
            unpricedTokens = try values.decodeIfPresent(Int.self, forKey: .unpricedTokens) ?? 0
            estimatedUSD = try values.decodeIfPresent(Double.self, forKey: .estimatedUSD) ?? 0
            reportedUSD = try values.decodeIfPresent(Double.self, forKey: .reportedUSD) ?? 0
            estimatedRequests = try values.decodeIfPresent(Int.self, forKey: .estimatedRequests) ?? 0
            missingCost = try values.decodeIfPresent(Int.self, forKey: .missingCost) ?? 0
        }
    }

    private let lock = NSLock()
    private var total: Total
    private var generation = UUID()
    private var changed: (@Sendable () -> Void)?

    public init(total: Total = Total()) { self.total = total }

    public var snapshot: Total {
        lock.lock(); defer { lock.unlock() }
        return total
    }

    public func onChange(_ callback: @escaping @Sendable () -> Void) {
        lock.lock(); defer { lock.unlock() }
        changed = callback
    }

    public func setEnabled(_ enabled: Bool) {
        lock.lock()
        if enabled && !total.enabled && total.requests == 0 { total.since = Date() }
        total.enabled = enabled
        let callback = changed
        lock.unlock()
        callback?()
    }

    public func reset() {
        lock.lock()
        let enabled = total.enabled
        total = Total()
        total.enabled = enabled
        generation = UUID() // Replies from requests before reset cannot repopulate the total.
        let callback = changed
        lock.unlock()
        callback?()
    }

    /// Capture opt-in at dispatch. Disabling stops new requests; admitted replies still settle.
    public func beginRequest() -> UUID? {
        lock.lock()
        guard total.enabled else { lock.unlock(); return nil }
        total.requests += 1
        total.missingUsage += 1
        total.missingCost += 1
        let ticket = generation
        let callback = changed
        lock.unlock()
        callback?()
        return ticket
    }

    public func received(_ ticket: UUID?, model: String, inputTokens: Int?, reportedCostUSD: Double?) {
        guard let ticket else { return }
        lock.lock()
        guard ticket == generation else { lock.unlock(); return }
        if let inputTokens, inputTokens >= 0 {
            total.missingUsage -= 1
            total.inputTokens += inputTokens
        }
        if let reportedCostUSD, reportedCostUSD.isFinite, reportedCostUSD >= 0 {
            total.reportedUSD += reportedCostUSD
            total.missingCost -= 1
        } else if let inputTokens, inputTokens >= 0, Self.pricedModels.contains(model) {
            total.estimatedUSD += Double(inputTokens) * Self.inputUSDPerMillion / 1_000_000
            total.estimatedRequests += 1
            total.missingCost -= 1
        } else if let inputTokens, inputTokens >= 0 {
            total.unpricedTokens += inputTokens
        }
        let callback = changed
        lock.unlock()
        callback?()
    }
}
