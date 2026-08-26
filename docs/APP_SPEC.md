# App Spec — iOS (Swift)

## Dependency setup

Single external dependency for MVP: [`stellar-ios-mac-sdk`](https://github.com/Soneso/stellar-ios-mac-sdk) (Soneso), added via Swift Package Manager.

```swift
.package(url: "https://github.com/Soneso/stellar-ios-mac-sdk.git", from: "3.10.0")
```

`3.10.0` was confirmed current (via GitHub tags) as of Phase 0 — check the repo's Releases page for the current tag before re-pinning; treat the number above as a known-working floor, not a fixed target. Module name is lowercase: `import stellarsdk`.

This SDK has full Horizon coverage and full Soroban RPC coverage as of research time (build, sign, simulate, and submit Soroban transactions; query classic account/operation data) with async/await APIs throughout. **Don't build a second, hand-rolled RPC client** — route everything through this SDK.

Deployment target: the SDK's stated minimum is iOS 15 / macOS 12. `app/Package.swift` currently declares `.iOS(.v16)` (plus `.macOS(.v12)` so `swift build` also works on the dev host, since this is an SPM-first package — see below) as a placeholder; revisit against actual SwiftUI/state-management API needs in Phase 4 and record the final decision + reasoning here.

## Folder structure

**Phase 0 decision: SPM-first.** `app/Package.swift` defines a `StellarRep` library target; there is no `.xcodeproj` in this repo. Confirmed building both via `swift build` (macOS host) and `xcodebuild -scheme StellarRep -destination 'generic/platform=iOS Simulator'` with a bare `import stellarsdk`. Xcode can open the `app/` folder directly (it treats `Package.swift` as an implicit project) for anything needing the Simulator or a UI. Revisit only if Phase 6 UI work turns out to need something SPM-first can't give it (e.g. asset catalogs beyond what SPM resources support, or an actual installable `.app` for device testing).

```
app/
├── Package.swift                 (SPM-first — see decision above)
├── Sources/StellarRep/
│   ├── App/
│   │   └── StellarRepApp.swift
│   ├── Core/
│   │   ├── KeychainWalletManager.swift    // keypair generation/import, Keychain storage only
│   │   ├── ReputationService.swift        // wraps the 3 contract calls
│   │   └── NetworkConfig.swift            // testnet endpoints, network passphrase, Friendbot URL — single source of truth, nothing hardcoded elsewhere
│   ├── Models/
│   │   ├── WorkerProfile.swift            // mirrors the contract's WorkerProfile
│   │   └── Review.swift
│   ├── Features/
│   │   ├── Onboarding/
│   │   │   ├── OnboardingView.swift
│   │   │   └── OnboardingViewModel.swift
│   │   ├── Profile/
│   │   │   ├── ProfileView.swift
│   │   │   └── ProfileViewModel.swift
│   │   ├── SubmitReview/
│   │   │   ├── SubmitReviewView.swift
│   │   │   └── SubmitReviewViewModel.swift
│   │   └── Settings/
│   │       └── SettingsView.swift          // network indicator, key export/backup warnings
│   └── Resources/
│       └── Assets.xcassets
├── Generated/                              // Phase 3 output, if stellar-contract-bindings is used — gitignore or commit deliberately, your call
└── Tests/StellarRepTests/
    ├── ReputationServiceTests.swift        // mocked service, no network
    └── KeychainWalletManagerTests.swift
```

## Service layer

```swift
protocol ReputationServiceProtocol {
    func registerWorker(signer: KeyPair) async throws
    func submitReview(worker: String, reviewer: KeyPair, jobId: String, rating: UInt32) async throws
    func getReputation(worker: String) async throws -> WorkerProfile
}
```

`registerWorker` and `submitReview` go through the full Soroban transaction lifecycle: simulate → sign locally with the provided `KeyPair` → submit → poll until confirmed. `getReputation` is simulate-only — no signature, no fee, no submitted transaction.

Consider generating a typed client from the deployed contract in Phase 3 (`stellar-contract-bindings swift`) and using it as `ReputationService`'s implementation rather than hand-encoding contract call parameters — but treat the hand-written protocol above as the app-facing interface either way, so ViewModels never depend directly on generated code or on `stellarsdk` types.

## Screens

1. **Onboarding** — create-new vs. import-existing wallet. On create: generate a keypair, store in Keychain, fund via Friendbot. The Friendbot funding action must be visibly disabled/hidden if the app is ever pointed at a non-testnet network.
2. **Profile / Look Up** — search by address (paste or scan); shows aggregate rating, job count, and a paginated review list. Include a "share my profile" affordance (e.g. a QR of the user's own address) since this feeds directly into the review handoff below.
3. **Submit Review** — the reviewer-side flow: scan or paste the worker's address + `job_id`, pick a 1–5 rating, sign and submit, show pending → confirmed states distinctly (don't collapse them into one "loading" spinner — a pending Soroban tx can still fail after simulation succeeded, and the user should see that transition).
4. **Settings** — a persistent, hard-to-miss network indicator (should read "Testnet" throughout MVP — this should not be a small label a reviewer could miss), plus key export/backup warning copy.

## State management

Simple MVVM. Two reasonable choices depending on the deployment target decided in Phase 4:
- iOS 17+: `@Observable` view models — less boilerplate, newer pattern.
- iOS 15+ (matches the SDK's stated floor): `ObservableObject` / `@Published` — broader compatibility.

Pick one, don't mix both patterns in the same codebase, and note the choice + reasoning here once Phase 4 makes it.

## Testing approach

- **Unit tests** for ViewModels against a mocked `ReputationServiceProtocol` — these should never touch the network, testnet or otherwise, and should run fast enough to execute on every commit.
- **A small number of real integration tests** (or a manual test script if a full separate test target feels like overkill this early) that hit live testnet — these fulfill Phase 5's "one real end-to-end test" requirement. Keep these clearly separated from the unit test suite (a separate scheme/target, or an explicit flag) so CI can skip them when testnet is flaky without losing unit test coverage.
