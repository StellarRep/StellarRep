import Foundation
import Testing
import stellarsdk
@testable import StellarRep

/// Real, live-network tests against the deployed testnet contract — not
/// mocked, and going through `ReputationService` itself rather than the
/// raw generated client, so this exercises the actual production code path.
/// This is what proves Phase 5's "done when" bar in `docs/ROADMAP.md`: an
/// end-to-end register → submit review loop against live testnet, unattended.
@Suite
struct ReputationServiceIntegrationTests {
    @Test func registerAndSubmitReviewEndToEndAgainstLiveTestnet() async throws {
        let service = ReputationService()

        // Two fresh, funded testnet accounts — a worker cannot review
        // themself, so this needs two distinct signers, same as the manual
        // Phase 3 verification in contracts/reputation/DEPLOYED.md.
        let worker = try KeyPair.generateRandomKeyPair()
        let reviewer = try KeyPair.generateRandomKeyPair()
        _ = await NetworkConfig.sdk.accounts.createTestAccount(accountId: worker.accountId)
        _ = await NetworkConfig.sdk.accounts.createTestAccount(accountId: reviewer.accountId)
        // Give both Friendbot funding transactions a moment to settle
        // before building transactions against these accounts.
        try await Task.sleep(nanoseconds: 5_000_000_000)

        try await service.registerWorker(signer: worker)

        let jobId = "job\(Int.random(in: 1_000...999_999))"
        try await service.submitReview(worker: worker.accountId, reviewer: reviewer, jobId: jobId, rating: 4)

        let profile = try await service.getReputation(worker: worker.accountId, as: worker)
        #expect(profile.totalJobs == 1)
        #expect(profile.ratingSum == 4)
        #expect(profile.averageRating == 4.0)

        let reviews = try await service.getReviews(worker: worker.accountId, start: 0, limit: 10, as: worker)
        #expect(reviews.count == 1)
        #expect(reviews.first?.jobId == jobId)
        #expect(reviews.first?.reviewer == reviewer.accountId)
        #expect(reviews.first?.rating == 4)
    }

    @Test func registerTwiceSurfacesAsTypedContractError() async throws {
        let service = ReputationService()
        let worker = try KeyPair.generateRandomKeyPair()
        _ = await NetworkConfig.sdk.accounts.createTestAccount(accountId: worker.accountId)
        try await Task.sleep(nanoseconds: 5_000_000_000)

        try await service.registerWorker(signer: worker)

        do {
            try await service.registerWorker(signer: worker)
            Issue.record("expected the second registerWorker call to throw")
        } catch let error as ReputationServiceError {
            #expect(error == .contract(.AlreadyRegistered))
        }
    }
}
