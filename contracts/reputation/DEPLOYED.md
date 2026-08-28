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

### Swift bindings generation — resolved

`stellar-contract-bindings` 0.5.0b0 (the latest on PyPI) failed against this contract's spec with `Get contract specs failed: Unexpected trailing 2192 bytes in XDR data`. Traced to root cause rather than worked around: `metadata.py::parse_entries` passed the *entire remaining buffer* into a per-entry XDR parser that requires the buffer be fully consumed by exactly one entry — so it broke on any contract with more than one spec entry (i.e. almost any real contract), not something specific to this one.

Both this bug and a second one hit right after (multi-line `///` doc comments on contract items collapse onto one line, so continuation lines leak into the generated Swift as raw, uncommented source and fail to compile) were **already fixed on the upstream `main` branch** — `43fd4b9` and `c1b69d0` respectively — just not yet cut into a PyPI release. Filed [lightsail-network/stellar-contract-bindings#38](https://github.com/lightsail-network/stellar-contract-bindings/issues/38) asking for a release.

Installed from `main` directly (`pipx install git+https://github.com/lightsail-network/stellar-contract-bindings.git`) instead of PyPI to unblock this now. Regenerated bindings against the live contract above; `app/Sources/StellarRep/Generated/ReputationContract.swift` is committed and confirmed compiling via `swift build`. **Until a new PyPI release ships**, regenerating requires installing from `main` the same way — plain `pipx install stellar-contract-bindings` will reproduce the original failure.

## Dev identities (Phase 0 / Phase 3)

- Alias: `stellarrep-dev` (acts as the worker in manual testing)
  - Address: `GBO2M25UFYFVHUJGNDN7DPJFLEPFDXOFP7NU7SPAIOEQFYTDSIWCSKZP`
  - Funded via Friendbot on 2026-08-26.
- Alias: `stellarrep-reviewer` (acts as the reviewer in manual testing — `submit_review` requires `worker != reviewer`)
  - Address: `GBTZ3AQRYAJHZH5BPQMRTE3ELBFVGZOB2DFA5P7QPGS2P3DI7JNMNL52`
  - Funded via Friendbot on 2026-08-27.

Never record a mainnet contract ID or secret key in this file.
