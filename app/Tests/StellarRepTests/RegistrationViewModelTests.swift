import Testing
import stellarsdk
@testable import StellarRep

/// A `ReputationServiceProtocol` whose single call suspends until the test
/// explicitly resumes it — lets these tests observe the transient `.pending`
/// state deterministically, which a real network call never would.
///
/// `waitUntilCallStarted()` — not a fixed number of `Task.yield()` calls —
/// is what makes this deterministic: `startedSignal` is an unbounded
/// `AsyncStream`, so the `yield()` in `registerWorker` is buffered even if
/// the test hasn't started listening yet, and consuming one element always
/// means "the call has reached its suspension point," never a guess about
/// scheduling.
private final class ControllableReputationService: ReputationServiceProtocol, @unchecked Sendable {
    private var continuation: CheckedContinuation<Void, Error>?
    private let startedSignal = AsyncStream<Void>.makeStream()

    func registerWorker(signer: KeyPair) async throws {
        try await withCheckedThrowingContinuation { cont in
            self.continuation = cont
            self.startedSignal.continuation.yield()
        }
    }

    func waitUntilCallStarted() async {
        var iterator = startedSignal.stream.makeAsyncIterator()
        _ = await iterator.next()
    }

    func resume(throwing error: Error? = nil) {
        if let error {
            continuation?.resume(throwing: error)
        } else {
            continuation?.resume()
        }
    }

    func submitReview(worker: String, reviewer: KeyPair, jobId: String, rating: UInt32) async throws {
        fatalError("not exercised by these tests")
    }

    func getReputation(worker: String, as reader: KeyPair) async throws -> WorkerProfile {
        fatalError("not exercised by these tests")
    }

    func getReviews(worker: String, start: UInt32, limit: UInt32, as reader: KeyPair) async throws -> [Review] {
        fatalError("not exercised by these tests")
    }
}

@Suite
struct RegistrationViewModelTests {
    @Test func registerTransitionsThroughPendingToSucceeded() async throws {
        let mock = ControllableReputationService()
        let viewModel = await RegistrationViewModel(service: mock)
        let signer = try KeyPair.generateRandomKeyPair()

        let task = Task { await viewModel.register(signer: signer) }
        await mock.waitUntilCallStarted()
        #expect(await viewModel.state == .pending)

        mock.resume()
        await task.value

        #expect(await viewModel.state == .succeeded(EmptySuccess()))
    }

    @Test func registerSurfacesContractErrorDistinctlyFromNetworkError() async throws {
        let mock = ControllableReputationService()
        let viewModel = await RegistrationViewModel(service: mock)
        let signer = try KeyPair.generateRandomKeyPair()

        let task = Task { await viewModel.register(signer: signer) }
        await mock.waitUntilCallStarted()
        mock.resume(throwing: ReputationServiceError.contract(.AlreadyRegistered))
        await task.value

        #expect(await viewModel.state == .failed(.contract(.AlreadyRegistered)))
    }

    @Test func registerSurfacesNetworkErrorDistinctlyFromContractError() async throws {
        let mock = ControllableReputationService()
        let viewModel = await RegistrationViewModel(service: mock)
        let signer = try KeyPair.generateRandomKeyPair()

        let task = Task { await viewModel.register(signer: signer) }
        await mock.waitUntilCallStarted()
        mock.resume(throwing: ReputationServiceError.network("connection lost"))
        await task.value

        #expect(await viewModel.state == .failed(.network("connection lost")))
    }
}
