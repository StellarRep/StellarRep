/// App-facing mirror of the contract's `Review` (see `docs/CONTRACT_SPEC.md`).
/// Addresses are plain `G...` account-id strings, not `SCAddressXDR` —
/// ViewModels shouldn't need to know that type exists.
public struct Review: Equatable, Sendable {
    public let worker: String
    public let reviewer: String
    public let jobId: String
    public let rating: UInt32
    public let timestamp: UInt64

    public init(worker: String, reviewer: String, jobId: String, rating: UInt32, timestamp: UInt64) {
        self.worker = worker
        self.reviewer = reviewer
        self.jobId = jobId
        self.rating = rating
        self.timestamp = timestamp
    }
}
