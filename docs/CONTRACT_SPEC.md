# Contract Spec — Reputation Contract

This is a spec and reference skeleton, not copy-paste-final code. It's written to compile against a current `soroban-sdk`, but exact storage/event macro behavior shifts across SDK major versions — cross-check against the current SDK docs or the linked stellar-dev-skill during Phase 1–2 rather than trusting this file blindly. See `CLAUDE.md`'s ground rules on not hardcoding versions.

## Storage schema

Three logical entities, all in **persistent** storage (not `instance` — each worker/review should be independently rent-tracked rather than sharing one contract-wide entry; not `temporary` — reputation data needs to actually persist).

```rust
#[contracttype]
#[derive(Clone)]
pub struct WorkerProfile {
    pub total_jobs: u32,
    pub rating_sum: u64,   // sum of all ratings; average = rating_sum / total_jobs
    pub created_at: u64,   // ledger timestamp at registration
}

#[contracttype]
#[derive(Clone)]
pub struct Review {
    pub worker: Address,
    pub reviewer: Address,
    pub job_id: Symbol,
    pub rating: u32,       // 1–5
    pub timestamp: u64,
}

#[contracttype]
pub enum DataKey {
    Worker(Address),            // -> WorkerProfile
    Review(Address, Symbol),    // -> Review, keyed by (worker, job_id) — this composite key is what enforces "one review per job"
    ReviewIds(Address),         // -> Vec<Symbol>, ordered list of job_ids for a worker, for pagination
}
```

**Watch out — storage TTL.** Soroban persistent storage entries have a rent-like time-to-live; if not periodically extended, entries can be archived and become unreadable until restored. For a contract meant to hold reputation data indefinitely, decide during Phase 2 whether `submit_review` (or a separate maintenance call) needs to explicitly extend the TTL on the relevant `Worker` and `Review` entries. Confirm the current extension API (method names have shifted across SDK versions) against the current soroban-sdk docs or the linked stellar-dev-skill before implementing — don't guess the exact call signature from this document.

## Errors

```rust
#[contracterror]
#[derive(Clone, Copy)]
pub enum Error {
    AlreadyRegistered = 1,
    NotRegistered = 2,
    InvalidRating = 3,
    DuplicateReview = 4,
    SelfReview = 5,
}
```

## Events

```rust
#[contractevent]
pub struct WorkerRegistered {
    pub worker: Address,
    pub timestamp: u64,
}

#[contractevent]
pub struct ReviewSubmitted {
    pub worker: Address,
    pub reviewer: Address,
    pub job_id: Symbol,
    pub rating: u32,
}
```

`#[contractevent]` is a relatively recent macro — some SDK versions distinguish which fields are indexed "topics" vs. plain data. Check current usage before assuming every field here should be treated the same way.

## Functions

```rust
#[contract]
pub struct ReputationContract;

#[contractimpl]
impl ReputationContract {

    /// Worker registers themself. Must be signed by `worker`.
    pub fn register_worker(env: Env, worker: Address) -> Result<(), Error> {
        worker.require_auth();
        let key = DataKey::Worker(worker.clone());
        if env.storage().persistent().has(&key) {
            return Err(Error::AlreadyRegistered);
        }
        let profile = WorkerProfile {
            total_jobs: 0,
            rating_sum: 0,
            created_at: env.ledger().timestamp(),
        };
        env.storage().persistent().set(&key, &profile);
        // emit WorkerRegistered { worker, timestamp: profile.created_at }
        Ok(())
    }

    /// Reviewer submits a review for a worker's completed job. Must be signed by `reviewer`, NOT `worker`.
    pub fn submit_review(
        env: Env,
        worker: Address,
        reviewer: Address,
        job_id: Symbol,
        rating: u32,
    ) -> Result<(), Error> {
        reviewer.require_auth();

        if worker == reviewer {
            return Err(Error::SelfReview);
        }
        if rating < 1 || rating > 5 {
            return Err(Error::InvalidRating);
        }

        let worker_key = DataKey::Worker(worker.clone());
        let mut profile: WorkerProfile = env.storage().persistent()
            .get(&worker_key)
            .ok_or(Error::NotRegistered)?;

        let review_key = DataKey::Review(worker.clone(), job_id.clone());
        if env.storage().persistent().has(&review_key) {
            return Err(Error::DuplicateReview);
        }

        let review = Review {
            worker: worker.clone(),
            reviewer: reviewer.clone(),
            job_id: job_id.clone(),
            rating,
            timestamp: env.ledger().timestamp(),
        };
        env.storage().persistent().set(&review_key, &review);

        // append job_id to DataKey::ReviewIds(worker) list here — omitted for brevity,
        // needed for get_reviews pagination below

        profile.total_jobs += 1;
        profile.rating_sum += rating as u64;
        env.storage().persistent().set(&worker_key, &profile);

        // emit ReviewSubmitted { worker, reviewer, job_id, rating }
        Ok(())
    }

    /// Read-only. No auth required.
    pub fn get_reputation(env: Env, worker: Address) -> Result<WorkerProfile, Error> {
        env.storage().persistent()
            .get(&DataKey::Worker(worker))
            .ok_or(Error::NotRegistered)
    }

    /// Read-only, paginated. No auth required.
    /// Reads the DataKey::ReviewIds(worker) list, slices [start..start+limit],
    /// fetches each Review by DataKey::Review(worker, job_id).
    pub fn get_reviews(env: Env, worker: Address, start: u32, limit: u32) -> Vec<Review> {
        // implementation: fetch ReviewIds(worker), slice, map each id to a Review lookup
        unimplemented!()
    }
}
```

## Testing plan

Every error variant needs a test that actually triggers it — a contract with only happy-path tests isn't meaningfully tested:

- `register_worker` succeeds on first call
- `register_worker` returns `AlreadyRegistered` on second call for the same address
- `submit_review` succeeds and correctly updates `total_jobs` / `rating_sum`
- `submit_review` returns `NotRegistered` if the worker was never registered
- `submit_review` returns `SelfReview` if `worker == reviewer`
- `submit_review` returns `InvalidRating` for 0 and for 6
- `submit_review` returns `DuplicateReview` for a repeated `(worker, job_id)`
- `submit_review` fails auth (panics / rejected) if not actually signed by `reviewer` — use `soroban-sdk`'s `testutils` auth-mocking to verify this explicitly rather than assuming `require_auth` works because it compiled
- `get_reputation` returns `NotRegistered` for an unknown address
- `get_reviews` pagination returns correct slices at boundary conditions (start=0, start beyond length, limit larger than remaining)

Run with `cargo test` inside the contract crate. Build the deployable artifact separately with `stellar contract build` (never `cargo build` directly for the deployable Wasm — the current tooling is explicit that `cargo build` doesn't apply the settings the Soroban runtime requires).
