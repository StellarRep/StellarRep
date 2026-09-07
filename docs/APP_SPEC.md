# App Spec — iOS (Swift)

## Dependency setup

Single external dependency for MVP: [`stellar-ios-mac-sdk`](https://github.com/Soneso/stellar-ios-mac-sdk) (Soneso), added via Swift Package Manager.

```swift
.package(url: "https://github.com/Soneso/stellar-ios-mac-sdk.git", from: "3.10.0")
```

`3.10.0` was confirmed current (via GitHub tags) as of Phase 0 — check the repo's Releases page for the current tag before re-pinning; treat the number above as a known-working floor, not a fixed target. Module name is lowercase: `import stellarsdk`.

This SDK has full Horizon coverage and full Soroban RPC coverage as of research time (build, sign, simulate, and submit Soroban transactions; query classic account/operation data) with async/await APIs throughout. **Don't build a second, hand-rolled RPC client** — route everything through this SDK.

Deployment target: the SDK's stated minimum is iOS 15 / macOS 12. **Phase 4 decision: iOS 16.** `app/Package.swift` declares `.iOS(.v16)` — chosen alongside the `ObservableObject`/`@Published` state-management decision below (broader-compatibility path over `@Observable`'s iOS 17 floor), with room to spare since nothing built so far actually needs iOS 17 APIs. `.macOS(.v12)` is also declared, but purely so `swift build`/`swift test` work on the dev host directly — it is not a real target platform for this app.

## Folder structure

**Phase 0 decision: SPM-first.** `app/Package.swift` defines a `StellarRep` library target; there is no `.xcodeproj` in this repo. Confirmed building both via `swift build` (macOS host) and `xcodebuild -scheme StellarRep -destination 'generic/platform=iOS Simulator'` with a bare `import stellarsdk`. Xcode can open the `app/` folder directly (it treats `Package.swift` as an implicit project) for anything needing the Simulator or a UI. Revisit only if Phase 6 UI work turns out to need something SPM-first can't give it (e.g. asset catalogs beyond what SPM resources support, or an actual installable `.app` for device testing).

**Phase 4 correction: the app entry point is its own target, not a subfolder of `StellarRep`.** The tree below originally put `App/StellarRepApp.swift` inside the `StellarRep` library target; that broke `swift test` — SwiftPM links a library target's `@main` type into every target that depends on it, including `StellarRepTests`, producing a duplicate `_main` symbol at link time. `Package.swift` now declares two products/targets: `StellarRep` (the library — Core/Features/everything else, no `@main`) and `StellarRepApp` (depends on `StellarRep`, holds only the entry point). `OnboardingView` had to become `public` for the app target to see it across the module boundary; the same will apply to whatever View Phase 6 wires up as the app's root.

```
app/
├── Package.swift                 (SPM-first — see decision above; two targets, see App entry point note above)
├── Sources/
│   ├── StellarRep/                        (library target — everything below is `import StellarRep`-visible; only what App/ needs is `public`)
│   │   ├── Core/
│   │   │   ├── KeychainWalletManager.swift    // keypair generation/import, Keychain storage only — Sendable, no mutable state
│   │   │   ├── ReputationService.swift        // wraps the generated ReputationContract client behind ReputationServiceProtocol
│   │   │   ├── ContractCallState.swift        // .idle/.pending/.succeeded/.failed — the reusable pattern every contract-calling ViewModel uses
│   │   │   └── NetworkConfig.swift            // testnet endpoints, network passphrase, Friendbot URL, the deployed contract ID — single source of truth, nothing hardcoded elsewhere
│   │   ├── Models/
│   │   │   ├── WorkerProfile.swift            // mirrors the contract's WorkerProfile
│   │   │   └── Review.swift
│   │   ├── Features/
│   │   │   ├── Onboarding/
│   │   │   │   ├── OnboardingView.swift       // public — App/ instantiates it
│   │   │   │   └── OnboardingViewModel.swift
│   │   │   ├── Registration/
│   │   │   │   └── RegistrationViewModel.swift // registers a wallet as a worker — Phase 5's first real ContractCallState consumer; no View yet, that's Phase 6
│   │   │   ├── Profile/
│   │   │   │   ├── ProfileView.swift
│   │   │   │   └── ProfileViewModel.swift
│   │   │   ├── SubmitReview/
│   │   │   │   ├── SubmitReviewView.swift
│   │   │   │   └── SubmitReviewViewModel.swift
│   │   │   └── Settings/
│   │   │       └── SettingsView.swift          // network indicator, key export/backup warnings
│   │   ├── Generated/
│   │   │   └── ReputationContract.swift        // Phase 3 output (stellar-contract-bindings) — see Service layer section below
│   │   └── Resources/
│   │       └── Assets.xcassets
│   └── StellarRepApp/
│       └── StellarRepApp.swift                 // @main — the only file in this target
└── Tests/StellarRepTests/                       (depends on StellarRep only, never StellarRepApp)
    ├── KeychainWalletManagerTests.swift          // fast, offline, real Keychain
    ├── OnboardingIntegrationTests.swift           // real, unmocked — hits live Friendbot + Horizon
    ├── RegistrationViewModelTests.swift           // fast, offline — mocked ReputationServiceProtocol, proves pending/contract-error/network-error states
    └── ReputationServiceIntegrationTests.swift    // real, unmocked — register → submit_review → get_reputation → get_reviews against live testnet
```

## Service layer

**Phase 5 — implemented as designed below**, on top of the Phase 3 generated `ReputationContract` client rather than hand-encoded calls (see the resolved Phase 3 finding further down):

```swift
public protocol ReputationServiceProtocol: Sendable {
    func registerWorker(signer: KeyPair) async throws
    func submitReview(worker: String, reviewer: KeyPair, jobId: String, rating: UInt32) async throws
    func getReputation(worker: String, as reader: KeyPair) async throws -> WorkerProfile
    func getReviews(worker: String, start: UInt32, limit: UInt32, as reader: KeyPair) async throws -> [Review]
}
```

`registerWorker` and `submitReview` go through the full Soroban transaction lifecycle: simulate → sign locally with the provided `KeyPair` → submit → poll until confirmed. `getReputation`/`getReviews` are simulate-only — no signature, no fee, no submitted transaction — but `stellarsdk`'s generated client still needs a fee-paying source account to build the transaction envelope even for a pure read, hence the `as reader: KeyPair` parameter on both. All four confirmed against the live testnet contract: manually in Phase 3, and end-to-end through this exact service in Phase 5 (`ReputationServiceIntegrationTests.swift`).

**Error handling.** `stellarsdk` has no structured type for a contract's own `Err(...)` return — confirmed empirically, not assumed from docs: calling `register_worker` twice throws `AssembledTransactionError.simulationFailed(message: "Simulation failed with error: HostError: Error(Contract, #1)\n\n...")`, a plain diagnostic string, where `1` is `Error::AlreadyRegistered`'s discriminant. `ReputationService` regex-extracts that `Error(Contract, #N)` substring and maps `N` to the generated `ReputationContractErrorError` enum, producing a typed `ReputationServiceError.contract(...)` distinct from `.network(String)` — this is what lets a ViewModel actually tell "the contract rejected this for a specific reason" from "something about reaching it failed."

**Pending/failed state pattern.** `ContractCallState<Success: Equatable & Sendable>` (`.idle`/`.pending`/`.succeeded(Success)`/`.failed(ReputationServiceError)`) is the one pattern every contract-calling ViewModel should drive its UI off — see `Core/ContractCallState.swift`. `RegistrationViewModel` is the first real consumer: `state: ContractCallState<EmptySuccess>` (the `EmptySuccess` marker struct stands in for `Void`-returning calls, since `Void` itself isn't `Equatable`). Proven with a mocked `ReputationServiceProtocol` whose call suspends on a `CheckedContinuation` until the test resumes it — `RegistrationViewModelTests.swift` — which is also where a real synchronization bug got caught and fixed: a `Task.yield()`-count guess for "has the mock's call reached its suspension point yet" was an actual race that could silently strand the mock's continuation forever; replaced with a deterministic `AsyncStream`-buffered signal (`waitUntilCallStarted()`) that can't be lost regardless of scheduling.

**Phase 3 finding, resolved:** `stellar-contract-bindings swift` (0.5.0b0, latest on PyPI) initially failed against this contract's spec with two real upstream bugs — full detail, root cause, and the upstream issue filed (lightsail-network/stellar-contract-bindings#38) in `DEPLOYED.md`. Both are already fixed on the tool's `main` branch, just not yet released to PyPI, so bindings were generated by installing from `main` directly. The generated client is committed at `app/Sources/StellarRep/Generated/ReputationContract.swift` and confirmed compiling via `swift build`. **Regenerating it** (e.g. after a contract change) needs the same git-main install until a new PyPI release ships; plain `pipx install stellar-contract-bindings` will reproduce the original failure.

`ReputationService` is the only file that imports the generated types or builds `SCAddressXDR`/`ClientOptions` — ViewModels depend on `ReputationServiceProtocol` and the app-facing `WorkerProfile`/`Review` models only, never on generated code or `stellarsdk` types directly.

## Screens

1. **Onboarding** — create-new vs. import-existing wallet. On create: generate a keypair, store in Keychain, fund via Friendbot. The Friendbot funding action must be visibly disabled/hidden if the app is ever pointed at a non-testnet network.
2. **Profile / Look Up** — search by address (paste or scan); shows aggregate rating, job count, and a paginated review list. Include a "share my profile" affordance (e.g. a QR of the user's own address) since this feeds directly into the review handoff below.
3. **Submit Review** — the reviewer-side flow: scan or paste the worker's address + `job_id`, pick a 1–5 rating, sign and submit, show pending → confirmed states distinctly (don't collapse them into one "loading" spinner — a pending Soroban tx can still fail after simulation succeeded, and the user should see that transition).
4. **Settings** — a persistent, hard-to-miss network indicator (should read "Testnet" throughout MVP — this should not be a small label a reviewer could miss), plus key export/backup warning copy.

## State management

**Phase 4 decision: `ObservableObject` / `@Published`, not `@Observable`.** `OnboardingViewModel` is `@MainActor final class OnboardingViewModel: ObservableObject` with a single `@Published private(set) var state: OnboardingState`. Chosen for the broader-compatibility floor (matches the SDK's stated iOS 15 minimum, and we're at iOS 16 — see Dependency setup above) over `@Observable`'s iOS 17 requirement; nothing built so far needed `@Observable`'s reduced boilerplate badly enough to justify raising the floor. Every future ViewModel should follow this same pattern — don't mix the two in this codebase.

## Testing approach

- **Unit tests** for ViewModels against a mocked `ReputationServiceProtocol` — these should never touch the network, testnet or otherwise, and should run fast enough to execute on every commit.
- **A small number of real integration tests** that hit live testnet, kept in their own files (`OnboardingIntegrationTests.swift`, `ReputationServiceIntegrationTests.swift`) separate from the mocked/offline suite, so CI can skip them when testnet is flaky without losing unit test coverage. Phase 5's own requirement — end-to-end register → submit_review against live testnet — is `ReputationServiceIntegrationTests.registerAndSubmitReviewEndToEndAgainstLiveTestnet()`, which goes through `ReputationService` itself (not the raw generated client) and additionally checks `getReputation`/`getReviews` reflect the write; a second test in the same file confirms a duplicate registration surfaces as the typed `ReputationServiceError.contract(.AlreadyRegistered)` end-to-end, not just in the mocked unit tests.
- **Fast, mocked ViewModel tests** against `ReputationServiceProtocol` never touch the network — `RegistrationViewModelTests.swift` is the concrete example, proving the `.pending` → `.succeeded`/`.failed` transitions and the contract-vs-network error distinction deterministically via a controllable mock (see the "Pending/failed state pattern" note in Service layer above for how that mock avoids the yield-count race that bit the first version of this test).
