import Foundation
import Testing
@testable import StellarRep

/// Real, live-network tests — deliberately not mocked. This is what
/// actually proves Phase 4's "done when" bar in `docs/ROADMAP.md`: a
/// brand-new install can create a funded testnet account and see a real
/// balance, with no manual CLI steps. Kept separate from
/// `KeychainWalletManagerTests` (which is offline/fast) since these hit
/// live testnet Friendbot + Horizon and can be slow or flaky if testnet is
/// having a bad day.
@Suite
final class OnboardingIntegrationTests {
    let wallet = KeychainWalletManager(service: "com.stellarrep.tests.\(UUID().uuidString)")

    deinit {
        try? wallet.deleteWallet()
    }

    @Test func createNewWalletEndToEndAgainstLiveTestnet() async throws {
        let viewModel = await OnboardingViewModel(wallet: wallet)

        await viewModel.createNewWallet()

        let state = await viewModel.state
        guard case .ready(let accountId, let balanceXLM) = state else {
            Issue.record("expected .ready, got \(state)")
            return
        }
        #expect(accountId.hasPrefix("G"))
        // Friendbot funds new testnet accounts with 10,000 XLM.
        #expect(Double(balanceXLM) == 10_000)
    }
}
