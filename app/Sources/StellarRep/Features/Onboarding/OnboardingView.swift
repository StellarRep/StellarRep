import SwiftUI

/// Create-new vs. import-existing wallet, per `docs/APP_SPEC.md`'s Onboarding
/// screen. Deliberately minimal for Phase 4 — this is the wallet/account
/// layer, not the polished UI pass that comes in Phase 6.
public struct OnboardingView: View {
    @StateObject private var viewModel = OnboardingViewModel()
    @State private var importSeedInput = ""
    @State private var showImportField = false

    public init() {}

    public var body: some View {
        VStack(spacing: 20) {
            Text("StellarRep")
                .font(.largeTitle.bold())

            // The persistent, hard-to-miss network indicator APP_SPEC.md
            // calls for lives on Settings (Phase 6); this is an early,
            // narrower version of the same idea for the one screen that
            // exists so far.
            Text(NetworkConfig.isTestnet ? "Testnet" : "⚠️ Not Testnet")
                .font(.caption.bold())
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.orange.opacity(0.2)))

            switch viewModel.state {
            case .idle:
                idleContent

            case .working:
                ProgressView("Working…")

            case .ready(let accountId, let balanceXLM):
                readyContent(accountId: accountId, balanceXLM: balanceXLM)

            case .failed(let error):
                failedContent(error)
            }
        }
        .padding()
        .task {
            await viewModel.loadExistingWalletIfPresent()
        }
    }

    private var idleContent: some View {
        VStack(spacing: 16) {
            Button("Create New Wallet") {
                Task { await viewModel.createNewWallet() }
            }
            .buttonStyle(.borderedProminent)

            if showImportField {
                TextField("Secret seed (S…)", text: $importSeedInput)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                Button("Import") {
                    Task { await viewModel.importWallet(secretSeed: importSeedInput) }
                }
                .buttonStyle(.bordered)
            } else {
                Button("Import Existing Wallet") {
                    showImportField = true
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private func readyContent(accountId: String, balanceXLM: String) -> some View {
        VStack(spacing: 8) {
            Text("Account")
                .font(.headline)
            Text(accountId)
                .font(.caption.monospaced())
                .multilineTextAlignment(.center)
                .textSelection(.enabled)
            Text("\(balanceXLM) XLM")
                .font(.title2.bold())
        }
    }

    private func failedContent(_ error: OnboardingError) -> some View {
        VStack(spacing: 12) {
            Text("Something went wrong")
                .font(.headline)
            Text(message(for: error))
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Try Again") {
                Task { await viewModel.loadExistingWalletIfPresent() }
            }
        }
    }

    private func message(for error: OnboardingError) -> String {
        switch error {
        case .wallet(.walletAlreadyExists):
            return "A wallet already exists on this device."
        case .wallet(.noWalletFound):
            return "No wallet found."
        case .wallet(.invalidSecretSeed):
            return "That doesn't look like a valid secret seed."
        case .wallet(.keychainFailure):
            return "Couldn't access the device Keychain."
        case .network(let message):
            return message
        }
    }
}
