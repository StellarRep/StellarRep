# Deployed Instances

## Testnet (Phase 3)

- **Contract ID:** `CASDNMYRVVFRTCS23GK2M77VP3W2YCB6NXKT33KL5ZIX6VW4W4TYEPOM`
- **Wasm hash:** `3753fbec9df7a49206d5813a4a66ad72ccd57b9c95072783a3193e44979bfcd0`
- **Network:** Test SDF Network ; September 2015
- **Deployed:** 2026-08-27, from `contracts/reputation/target/wasm32v1-none/release/reputation.wasm`
- Explorer: https://lab.stellar.org/r/testnet/contract/CASDNMYRVVFRTCS23GK2M77VP3W2YCB6NXKT33KL5ZIX6VW4W4TYEPOM

### Manual verification (all four functions invoked against this instance)

| Function | Kind | Tx hash | Result |
|---|---|---|---|
| `register_worker` | write | [`2d6caa0e...`](https://stellar.expert/explorer/testnet/tx/2d6caa0e5f810a9f2fd582787f0c4c8f062ceb7c30c31b432675867f306bf475) | `WorkerRegistered` event emitted for `stellarrep-dev` |
| `submit_review` | write | [`034efed0...`](https://stellar.expert/explorer/testnet/tx/034efed038eafb8668a1220e9c8fb72c2dde3e4f4fa43bef709de8f9cef94f17) | `ReviewSubmitted` event emitted (`job1`, rating 5) |
| `get_reputation` | read | simulate-only, no tx (by design — see `docs/APP_SPEC.md`) | Returned `{total_jobs: 1, rating_sum: 5}` — matches the write above |
| `get_reviews` | read | simulate-only, no tx | Returned the `job1` review with correct worker/reviewer/rating |

Confirmed on-chain state actually changed, not just that the CLI returned success: `get_reputation` after `submit_review` reflects the review (`total_jobs` went 0→1, `rating_sum` went 0→5), and `get_reviews` returns the exact review just submitted.

### Swift bindings generation — attempted, not usable yet

`stellar-contract-bindings` (0.5.0b0, the latest available on PyPI as of this writing) fails against this contract's spec: `Get contract specs failed: Unexpected trailing 2192 bytes in XDR data`. This looks like the tool's XDR contract-spec parser hasn't caught up with a newer entry kind — plausibly the ones `#[contractevent]` (a relatively new macro, per `docs/CONTRACT_SPEC.md`) adds under `soroban-sdk` 27.0.6. Not pursued further since it's explicitly optional in `docs/ROADMAP.md` Phase 3, and the roadmap's own caution ("sanity-check the output actually compiles before relying on it") is moot if it doesn't generate at all. `ReputationService` in Phase 5 will be hand-written on top of `stellarsdk` directly instead. Worth filing as an upstream issue (lightsail-network/stellar-contract-bindings) once this repo has a GitHub remote to reference from.

## Dev identities (Phase 0 / Phase 3)

- Alias: `stellarrep-dev` (acts as the worker in manual testing)
  - Address: `GBO2M25UFYFVHUJGNDN7DPJFLEPFDXOFP7NU7SPAIOEQFYTDSIWCSKZP`
  - Funded via Friendbot on 2026-08-26.
- Alias: `stellarrep-reviewer` (acts as the reviewer in manual testing — `submit_review` requires `worker != reviewer`)
  - Address: `GBTZ3AQRYAJHZH5BPQMRTE3ELBFVGZOB2DFA5P7QPGS2P3DI7JNMNL52`
  - Funded via Friendbot on 2026-08-27.

Never record a mainnet contract ID or secret key in this file.
