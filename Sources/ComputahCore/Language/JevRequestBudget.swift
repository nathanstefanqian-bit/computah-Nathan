import Foundation

public final class JevRequestBudget: @unchecked Sendable {
    public let limit: Int

    private let lock = NSLock()
    private var admitted = 0

    public init(limit: Int) {
        precondition(limit > 0)
        self.limit = limit
    }

    public var used: Int {
        lock.lock()
        defer { lock.unlock() }
        return admitted
    }

    public func admit() throws {
        lock.lock()
        defer { lock.unlock() }
        guard admitted < limit else { throw JevFailure.requestLimit(limit) }
        admitted += 1
    }
}
