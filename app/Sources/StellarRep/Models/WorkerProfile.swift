/// App-facing mirror of the contract's `WorkerProfile` (see
/// `docs/CONTRACT_SPEC.md`). ViewModels depend on this, never on the
/// generated `ReputationContractWorkerProfile` — `ReputationService` is the
/// only place that translates between them.
public struct WorkerProfile: Equatable, Sendable {
    public let totalJobs: UInt32
    public let ratingSum: UInt64
    public let createdAt: UInt64

    public init(totalJobs: UInt32, ratingSum: UInt64, createdAt: UInt64) {
        self.totalJobs = totalJobs
        self.ratingSum = ratingSum
        self.createdAt = createdAt
    }

    /// `nil` for a worker with no reviews yet, rather than dividing by zero.
    public var averageRating: Double? {
        totalJobs == 0 ? nil : Double(ratingSum) / Double(totalJobs)
    }
}
