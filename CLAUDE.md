# StellarRep — Project Context for Claude Code

> Working name: **StellarRep**. Rename freely — if you do, update this header and the Xcode/SPM product name together so they don't drift apart.

## What this is

A native iOS app (Swift) backed by a Soroban smart contract (Rust) that gives gig and freelance workers a **portable, on-chain reputation record on Stellar** — job counts and ratings that live on-chain instead of being locked inside one marketplace's private database. It's being built as a repo submission to the **Stellar Wave Program** (Drips × Stellar Development Foundation): https://www.drips.network/wave/stellar

## Why this project, why this category

The Wave Program approves repos across a handful of recurring categories: escrow, payments/payroll, RWA/DeFi, crowdfunding, freelance marketplaces. At the time this project was scoped, escrow and payments were heavily saturated (5+ approved repos each — Trustless-Work, SafeTrust front+back, Sub-Rosa, Stellar-Rent, kindfi in escrow alone), while **on-chain identity/reputation had no dedicated entry** in the approved-repo list. OFFER-HUB (an already-approved freelance marketplace) is evidence the underlying use case — freelance/gig work on Stellar — is one the program already funds; this project builds the reputation layer nobody had claimed yet.

Every repo on the approved list at scoping time was TypeScript/web-first with Rust contracts underneath. A genuinely native Swift app is a differentiator on its own, independent of category.

## Current status

**Phase 0 — done.** Git repo initialized (branch `main`); docs moved under `docs/`; Rust 1.97.1 + `wasm32v1-none` target confirmed; `stellar-cli` 27.1.0 installed via Homebrew; `contracts/` scaffolded as a Cargo workspace with the `reputation` contract (`contracts/reputation`), empty build passes (`stellar contract build`, 583-byte wasm); funded testnet dev identity created (alias `stellarrep-dev`, see `contracts/reputation/DEPLOYED.md`); `app/` scaffolded as an SPM-first package (`app/Package.swift`) with `stellar-ios-mac-sdk` 3.10.0 as a dependency — `import stellarsdk` confirmed building both on the macOS host (`swift build`) and for iOS Simulator (`xcodebuild -scheme StellarRep -destination 'generic/platform=iOS Simulator'`). Monorepo confirmed (contract + app in one repo, as this doc set assumes — no split). Next: **Phase 1 — Contract: Data Model & `register_worker`**, per `docs/ROADMAP.md`. Update this section as phases complete so anyone (human or Claude) picking this repo back up knows where to resume without re-reading everything.

## Tech stack

| Layer | Choice | Notes |
|---|---|---|
| Smart contract | Rust + `soroban-sdk`, built/deployed via `stellar-cli` | The runtime is still called "Soroban" in tooling and docs even though it's no longer marketed as a separate brand — see `docs/CONTRACT_SPEC.md`. |
| iOS app | Swift, SwiftUI | Native only. No Flutter/RN in this repo — that was the original plan for the underlying concept but this repo is Swift-only. |
| Stellar connectivity | [`stellar-ios-mac-sdk`](https://github.com/Soneso/stellar-ios-mac-sdk) (`import stellarsdk`) | Community-maintained (Soneso), actively developed. Has full Horizon **and** full Soroban RPC coverage as of research time — don't hand-roll a raw JSON-RPC client, this SDK already covers contract simulate/sign/send/poll. |
| Network target (MVP) | Stellar **Testnet** only | No mainnet keys, no mainnet contract ID, no real funds anywhere in this repo until a deliberate later decision. |

## Ground rules

1. **Testnet only until told otherwise.** Never wire in a mainnet secret key or prompt the user for one.
2. **Don't trust hardcoded versions in these docs.** Soroban's SDK major version tracks the network protocol version and moves fast; a version that was current when this doc set was written may not be current when you're actually building. Resolve current versions from crates.io / the SDK repos / SPM at build time. Every place this matters is flagged inline in `CONTRACT_SPEC.md` and `APP_SPEC.md`.
3. **Small, real, and working beats large and mocked.** Wave Program review looks for genuine functionality, not UI mockups. A 3-function contract that actually deploys and passes tests beats a 10-function contract that doesn't compile.
4. **Seed issues as you go.** Getting a repo approved into the Program depends partly on having well-scoped open issues for other contributors to pick up. Phase 7 in the roadmap covers this explicitly, but if a genuine v2 item surfaces earlier (see "Non-goals" in `docs/ARCHITECTURE.md`), open the issue then rather than batching everything at the end.
5. **This doc set is a starting frame, not gospel.** Where reality — an SDK quirk, a testnet outage, a cleaner pattern you find mid-build — contradicts what's written here, follow reality and update the doc to match. Stale docs are worse than no docs.

## Where things live

```
.
├── CLAUDE.md                 ← you are here
├── docs/
│   ├── ROADMAP.md             ← phased build plan — start here for "what do I do first"
│   ├── ARCHITECTURE.md        ← system design, data flow, security posture, non-goals
│   ├── CONTRACT_SPEC.md       ← Soroban contract: storage, functions, errors, events
│   └── APP_SPEC.md            ← Swift app: structure, screens, SDK usage
├── contracts/                 ← not yet created — Phase 1
└── app/                       ← not yet created — Phase 4
```

## Useful external references

- Stellar Wave Program, approved-repos board: https://www.drips.network/wave/stellar/repos
- Wave Program docs (lifecycle, rules, rewards): https://docs.drips.network/wave/
- Soroban smart contract overview: https://developers.stellar.org/docs/build/smart-contracts/overview
- Official agent-oriented Soroban skill — written specifically for coding agents, worth reading directly rather than relying on this doc set alone: https://github.com/stellar/stellar-dev-skill/blob/main/skills/smart-contracts/SKILL.md
- Stellar iOS/Mac SDK (Soneso): https://github.com/Soneso/stellar-ios-mac-sdk
- Swift contract-binding generator (optional — generates a typed Swift client from a deployed contract, can reduce hand-written glue code): https://github.com/lightsail-network/stellar-contract-bindings
