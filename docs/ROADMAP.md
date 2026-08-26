# Roadmap

Nine phases, meant to be worked in order but not necessarily in one sitting or one session. Each phase has a goal, a checklist, and a "definition of done" — don't move on until done is actually true, since later phases assume earlier ones genuinely work rather than mostly work.

A timing note up front: read it before planning around a specific Wave number — see the bottom of this file.

---

## Phase 0 — Project Initialization & Tooling

**Goal:** a working, verified dev environment and a correct-but-empty repo skeleton. Nothing product-shaped yet. Every later phase assumes the tools in this phase exist and work — don't skip ahead on the assumption they will.

- [ ] Confirm Rust toolchain: `rustc --version`. Soroban contracts currently need Rust 1.84+ for the `wasm32v1-none` target — verify the current minimum against `soroban-sdk`'s README rather than trusting that number blindly.
- [ ] Install/confirm `stellar-cli` (the unified CLI — this replaced the old standalone `soroban-cli` binary for build/deploy/invoke workflows): `stellar --version`. If missing, check current install instructions at crates.io/crates/stellar-cli — install method shifts between releases, don't assume a single command is permanently correct.
- [ ] Add the Wasm target: `rustup target add wasm32v1-none`
- [ ] Scaffold the contract workspace under `contracts/`. `stellar contract init <name>` is the standard scaffolding command, but check `stellar contract init --help` first — it may expect to create its own root directory rather than initialize into an existing one, in which case scaffold into a temp location and move the generated contract subfolder into this repo's `contracts/`.
- [ ] Build the empty scaffolded contract (`stellar contract build`) before writing any real logic — this is the actual proof the toolchain works, not just that it installed.
- [ ] Create a funded testnet identity for deploying/testing: `stellar keys generate <name> --network testnet --fund` (this creates a keypair and funds it via Friendbot in one step). Confirm the account is real: `stellar keys address <name>` then check it on a testnet explorer.
- [ ] Confirm Xcode is available and note the version (`xcodebuild -version`). Create the iOS app target under `app/` — either an `.xcodeproj` via Xcode, or an SPM-first package if you'd rather start there. Record which you chose in `docs/APP_SPEC.md`'s status notes, since it changes how dependencies get added.
- [ ] Add `stellar-ios-mac-sdk` as a Swift Package dependency to the app target (see `docs/APP_SPEC.md` for the exact package URL) and confirm the target builds with nothing but a bare `import stellarsdk` in it. This proves the dependency actually resolves before anything real gets built on top of it.
- [ ] Repo hygiene: `.gitignore` covering Xcode + SPM + Rust artifacts (`.build/`, `DerivedData/`, `*.xcuserstate`, `target/`, `.swiftpm/`), a short top-level `README.md` that just points to `CLAUDE.md`, and confirm `CLAUDE.md` + `docs/` are committed.
- [ ] Decide and record: contract and app in one repo (monorepo — what the rest of this doc set assumes) or two separate repos? If you split them, update the tree diagram in `CLAUDE.md` to match before continuing.

**Definition of done:** a fresh clone of the repo can run `stellar contract build` inside `contracts/reputation` and get a successful empty build, and can open and build the iOS app target with the SDK dependency resolved — with zero product logic written anywhere yet.

---

## Phase 1 — Contract: Data Model & `register_worker`

- Define `WorkerProfile`, `Review`, and the `DataKey` storage-key enum as `#[contracttype]`s per `docs/CONTRACT_SPEC.md`.
- Implement `register_worker`, backed by persistent storage.
- Unit tests: registering once succeeds; registering twice hits the decision recorded in the spec (error vs. no-op — pick one and document why).
- `stellar contract build` succeeds; `cargo test` passes.

**Done when:** a fresh test run registers a worker and reads back a correctly-initialized profile, with no manual steps.

## Phase 2 — Contract: Reviews & Reputation Read Path

- Implement `submit_review` — reviewer-signed (`require_auth` on the *reviewer*, not the worker), rating bounds checked, self-review blocked, duplicate `job_id` blocked.
- Implement `get_reputation` and a paginated `get_reviews`.
- Wire the `contracterror` enum and the two `contractevent`s (`WorkerRegistered`, `ReviewSubmitted`) per the spec.
- Read the "Storage/TTL" concern flagged in `CONTRACT_SPEC.md` and decide whether review/profile entries need explicit TTL extension so they don't get archived.
- Unit tests for every failure path listed in the spec, not just the happy path — a contract that only has happy-path tests isn't actually tested.

**Done when:** every error variant in the spec has a test that actually triggers it.

## Phase 3 — Testnet Deployment & Manual Verification

- `stellar contract deploy` to testnet. Record the resulting contract ID somewhere durable and non-secret (e.g. `contracts/reputation/DEPLOYED.md`) — never commit a mainnet ID or any secret key.
- Manually invoke all three read/write functions via `stellar contract invoke` against the deployed instance; confirm on-chain state actually changes as expected, not just that the CLI returns success.
- Optional but worth doing here rather than later: generate a typed Swift client from the deployed contract with `stellar-contract-bindings swift --contract-id <id> --rpc-url <testnet-rpc> --output ./app/Sources/Generated`. Sanity-check the output actually compiles before relying on it in Phase 5.

**Done when:** you can point at a real testnet contract ID and a transaction hash for each of the three functions having been called successfully.

## Phase 4 — iOS App: Wallet & Account Layer

- `KeychainWalletManager`: generate a new testnet keypair or import an existing one; store the secret key in Keychain only — never `UserDefaults`, never a plaintext file.
- Onboarding flow: create-new vs. import-existing.
- Fund newly-created testnet accounts via Friendbot from inside the app (gate this behind a testnet-only check so it can't ship live).
- Confirm the app fetches and displays a real, live account balance from Horizon via `stellarsdk`.

**Done when:** a brand-new install can create a funded testnet account and show its balance, with no manual CLI steps.

## Phase 5 — iOS App: Contract Integration

- Wrap the three contract calls behind a small `ReputationService` — either hand-written on top of `stellarsdk`'s Soroban support, or built on top of the Phase 3 generated bindings if those turned out usable.
- Handle the two realistic async states everywhere a contract call happens: pending/simulating, and failed (network error vs. contract error — these should surface differently to the user). Not just the happy path.
- Write one real integration test (or a manual test script, if a full test target is overkill at this point) that registers a worker and submits a review end-to-end against testnet.

**Done when:** that end-to-end integration test passes against live testnet, unattended.

## Phase 6 — Core UI Flows

- **Profile screen** — look up any address, show aggregate rating + job count + paginated review list.
- **Submit Review flow** — inherently two-party: the worker shares a job reference, the reviewer signs and submits. Pick one handoff mechanism for MVP (QR code, deep link, or manual address+job-id paste) and design around it explicitly rather than leaving it vague; note the others as v2 issues if you want them later.
- Basic empty/error/loading states throughout — not just happy-path screens.

**Done when:** two physical devices (or a device + simulator with two different test accounts) can complete a full register → review → view-reputation loop against testnet.

## Phase 7 — Hardening, Docs, Demo Data

- Write the actual repo `README.md` — what it is, how to run it, an unmissable testnet-only warning. This is what a Wave maintainer or reviewer sees first, before they read anything else in this repo.
- Populate a small demo dataset on testnet (a handful of registered workers with a few reviews each) so the app isn't empty on first open for a reviewer.
- Open the v2 items flagged as "Non-goals" in `docs/ARCHITECTURE.md` as real, well-scoped GitHub issues — dispute resolution, stake-weighted reviews, multi-marketplace aggregation, reviewer reputation, mainnet readiness, plus anything else that came up mid-build. This is what makes the repo useful to *other* Wave contributors, not just to you, and is part of what maintainers are evaluated on.

**Done when:** someone with zero context on this project could clone the repo, read the README, and understand what it does and how to try it, within a few minutes.

## Phase 8 — Wave Program Submission

- Re-read the current repo-application flow before submitting — it changes between Waves. (Wave 7, for instance, added a repo-rejection appeal process that didn't exist in earlier Waves — check for anything newer at https://www.drips.network/blog.)
- Apply the org/repo at https://www.drips.network/wave/maintainer-onboarding/install-app
- Confirm before submitting: real README, architecture doc, working testnet demo, 5+ well-scoped open issues. These are the concrete signals that were identified as actually moving approval, not just "looks finished."

**Done when:** the repo is submitted and you have a maintainer-dashboard confirmation, not just a form submission.

---

## A note on timing

At the time this roadmap was written (August 2026), Stellar Waves had been landing roughly monthly, consistently on the 19th–23rd (Wave 4: Apr 22, Wave 6: Jun 23, Wave 7: Jul 23). Extrapolating that pattern puts Wave 8 around Aug 23 — which is right around when this document was generated, meaning Wave 8 has likely already launched or is close to wrapping its 7-day cycle by the time you're reading this.

That's less of a problem than it sounds: per the Program's own lifecycle docs, repo *scoping and approval* is described as an early, ongoing step, not something tied to a single live Wave week — maintainers apply repos on a rolling basis, and an approved repo just becomes eligible for whichever Wave is live when its issues get picked up. So treat "Wave 8" as directional rather than a hard deadline. The realistic goal is: be approved and issue-ready by the time Phase 7 completes, and check https://www.drips.network/wave/stellar for the actual current Wave number before Phase 8, rather than assuming it's still 8.
