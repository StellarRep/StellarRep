import Foundation
import stellarsdk

/// The two things this screen can fail at, surfaced distinctly rather than
/// collapsed into one generic error — see APP_SPEC.md's note on pending vs.
/// failed states needing to read differently to the user.
enum OnboardingError: Error, Equatable {
    case wallet(KeychainWalletError)
    case network(String)
}

enum OnboardingState: Equatable {
    case idle
    case working
    case ready(accountId: String, balanceXLM: String)
    case failed(OnboardingError)
}

/// Drives the create-new vs. import-existing flow described in
/// `docs/APP_SPEC.md`'s Onboarding screen: generate or import a keypair,
/// fund it via Friendbot if it's new, then confirm a real balance reads back
/// from Horizon — the Phase 4 "done when" bar in `docs/ROADMAP.md`.
@MainActor
final class OnboardingViewModel: ObservableObject {
    @Published private(set) var state: OnboardingState = .idle

    private let wallet: KeychainWalletManager
    private let sdk: StellarSDK

    init(wallet: KeychainWalletManager = KeychainWalletManager(), sdk: StellarSDK = NetworkConfig.sdk) {
        self.wallet = wallet
        self.sdk = sdk
    }

    /// Generates a new wallet, funds it via Friendbot, and loads its balance.
    /// Friendbot only exists on testnet, so this is unconditionally gated on
    /// `NetworkConfig.isTestnet` — there is no code path here that could fund
    /// an account on a live network.
    func createNewWallet() async {
        state = .working
        do {
            let keyPair = try wallet.generateNewWallet()
            guard NetworkConfig.isTestnet else {
                // Unreachable today (isTestnet is a compile-time constant),
                // but a real check rather than an assumption: if this ever
                // becomes configurable, Friendbot funding must never fire
                // outside testnet.
                state = .failed(.network("Friendbot funding is testnet-only."))
                return
            }
            let fundingResult = await sdk.accounts.createTestAccount(accountId: keyPair.accountId)
            if case .failure(let error) = fundingResult {
                state = .failed(.network("Friendbot funding failed: \(error.message)"))
                return
            }
            await loadBalance(accountId: keyPair.accountId)
        } catch let error as KeychainWalletError {
            state = .failed(.wallet(error))
        } catch {
            state = .failed(.network(error.localizedDescription))
        }
    }

    /// Imports an existing wallet from its secret seed and loads its balance.
    /// Does not touch Friendbot — an imported account is assumed to already
    /// exist (and be funded, or not) on whatever network it came from.
    func importWallet(secretSeed: String) async {
        state = .working
        do {
            let keyPair = try wallet.importWallet(secretSeed: secretSeed)
            await loadBalance(accountId: keyPair.accountId)
        } catch let error as KeychainWalletError {
            state = .failed(.wallet(error))
        } catch {
            state = .failed(.network(error.localizedDescription))
        }
    }

    /// If a wallet already exists in the Keychain (returning user), loads
    /// its balance directly rather than showing the create/import choice.
    func loadExistingWalletIfPresent() async {
        guard wallet.hasWallet else { return }
        state = .working
        do {
            let keyPair = try wallet.loadWallet()
            await loadBalance(accountId: keyPair.accountId)
        } catch let error as KeychainWalletError {
            state = .failed(.wallet(error))
        } catch {
            state = .failed(.network(error.localizedDescription))
        }
    }

    private func loadBalance(accountId: String) async {
        let result = await sdk.accounts.getAccountDetails(accountId: accountId)
        switch result {
        case .success(let details):
            let native = details.balances.first { $0.assetType == "native" }
            state = .ready(accountId: accountId, balanceXLM: native?.balance ?? "0")
        case .failure(let error):
            state = .failed(.network("Could not load account: \(error.message)"))
        }
    }
}
