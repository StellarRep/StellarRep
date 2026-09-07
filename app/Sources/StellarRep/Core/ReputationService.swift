import stellarsdk

/// The two things a contract call can fail at, surfaced distinctly per
/// `docs/APP_SPEC.md`: the contract itself rejected the call (a real,
/// specific business-logic reason the user can be told directly), or
/// something about reaching/running it failed (network, RPC, a bad address).
/// `.contract` decoding is confirmed empirically (see `run(_:)` below), not
/// assumed from stellarsdk's docs.
public enum ReputationServiceError: Error, Equatable, Sendable {
    case contract(ReputationContractErrorError)
    case network(String)
    case invalidAddress(String)
}

/// App-facing interface to the reputation contract. ViewModels depend on
/// this protocol, never on `ReputationContract` (generated) or `stellarsdk`
/// types directly — see the "Service layer" note in `docs/APP_SPEC.md`.
public protocol ReputationServiceProtocol: Sendable {
    func registerWorker(signer: KeyPair) async throws
    func submitReview(worker: String, reviewer: KeyPair, jobId: String, rating: UInt32) async throws
    func getReputation(worker: String, as reader: KeyPair) async throws -> WorkerProfile
    func getReviews(worker: String, start: UInt32, limit: UInt32, as reader: KeyPair) async throws -> [Review]
}

/// Wraps the Phase 3 generated `ReputationContract` client. Builds a fresh
/// client per call rather than caching one per signer — simpler, and the
/// extra RPC round-trip to fetch the contract spec is not a bottleneck for
/// this app's call volume. Worth revisiting if that ever changes.
public struct ReputationService: ReputationServiceProtocol {
    private let contractId: String
    private let rpcUrl: String

    public init(contractId: String = NetworkConfig.reputationContractId, rpcUrl: String = NetworkConfig.sorobanRPCURL) {
        self.contractId = contractId
        self.rpcUrl = rpcUrl
    }

    public func registerWorker(signer: KeyPair) async throws {
        let contract = try await client(signer: signer)
        let worker = try address(signer.accountId)
        try await run { try await contract.registerWorker(worker: worker) }
    }

    public func submitReview(worker: String, reviewer: KeyPair, jobId: String, rating: UInt32) async throws {
        let contract = try await client(signer: reviewer)
        let workerAddr = try address(worker)
        let reviewerAddr = try address(reviewer.accountId)
        try await run {
            try await contract.submitReview(worker: workerAddr, reviewer: reviewerAddr, job_id: jobId, rating: rating)
        }
    }

    public func getReputation(worker: String, as reader: KeyPair) async throws -> WorkerProfile {
        let contract = try await client(signer: reader)
        let workerAddr = try address(worker)
        let profile = try await run { try await contract.getReputation(worker: workerAddr) }
        return WorkerProfile(totalJobs: profile.total_jobs, ratingSum: profile.rating_sum, createdAt: profile.created_at)
    }

    public func getReviews(worker: String, start: UInt32, limit: UInt32, as reader: KeyPair) async throws -> [Review] {
        let contract = try await client(signer: reader)
        let workerAddr = try address(worker)
        let reviews = try await run { try await contract.getReviews(worker: workerAddr, start: start, limit: limit) }
        return try reviews.map { review in
            guard let workerId = review.worker.accountId, let reviewerId = review.reviewer.accountId else {
                throw ReputationServiceError.invalidAddress("review contained a non-account address")
            }
            return Review(worker: workerId, reviewer: reviewerId, jobId: review.job_id, rating: review.rating, timestamp: review.timestamp)
        }
    }

    // MARK: - Helpers

    /// `stellarsdk`'s generated client always needs a fee-paying source
    /// account to build a transaction envelope, even for a pure read call
    /// (`getReputation`/`getReviews`) that never actually gets signed or
    /// submitted — hence every method above takes a `KeyPair`, not just the
    /// two that mutate state.
    private func client(signer: KeyPair) async throws -> ReputationContract {
        do {
            let options = ClientOptions(
                sourceAccountKeyPair: signer,
                contractId: contractId,
                network: .testnet,
                rpcUrl: rpcUrl
            )
            return try await ReputationContract.forClientOptions(options: options)
        } catch {
            throw ReputationServiceError.network("Could not connect to the reputation contract: \(String(describing: error))")
        }
    }

    private func address(_ accountId: String) throws -> SCAddressXDR {
        do {
            return try SCAddressXDR(accountId: accountId)
        } catch {
            throw ReputationServiceError.invalidAddress(accountId)
        }
    }

    /// Runs a generated-client call, translating a Soroban contract-level
    /// `Err(...)` into a typed `.contract` case and anything else into
    /// `.network`.
    ///
    /// stellarsdk has no structured type for a contract's own `Err(...)`
    /// return — it surfaces as a plain diagnostic string on
    /// `AssembledTransactionError.simulationFailed` (confirmed empirically
    /// against this deployed contract, not assumed from docs: calling
    /// `register_worker` twice throws exactly
    /// `simulationFailed(message: "Simulation failed with error: HostError:
    /// Error(Contract, #1)\n\n...")`, where 1 is `Error::AlreadyRegistered`'s
    /// discriminant). Parsing that `Error(Contract, #N)` substring is a real,
    /// if unfortunate, necessity until stellarsdk exposes this more directly.
    private func run<T>(_ body: () async throws -> T) async throws -> T {
        do {
            return try await body()
        } catch {
            if let code = Self.contractErrorCode(in: error),
               let contractError = ReputationContractErrorError(rawValue: code) {
                throw ReputationServiceError.contract(contractError)
            }
            throw ReputationServiceError.network(String(describing: error))
        }
    }

    private static func contractErrorCode(in error: Error) -> UInt32? {
        let message: String
        switch error {
        case AssembledTransactionError.simulationFailed(let m):
            message = m
        case SorobanClientError.invokeFailed(let m):
            message = m
        default:
            message = String(describing: error)
        }
        guard let matchRange = message.range(of: #"Error\(Contract, #\d+\)"#, options: .regularExpression),
              let digitsRange = message[matchRange].range(of: #"\d+"#, options: .regularExpression) else {
            return nil
        }
        return UInt32(message[matchRange][digitsRange])
    }
}
