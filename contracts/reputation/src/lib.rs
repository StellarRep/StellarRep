#![no_std]
use soroban_sdk::{
    contract, contracterror, contractevent, contractimpl, contracttype, Address, Env, Symbol,
};

/// A worker's aggregate on-chain reputation. `average = rating_sum / total_jobs`
/// (computed by callers — division is left out of storage to avoid lossy writes).
#[contracttype]
#[derive(Clone)]
pub struct WorkerProfile {
    pub total_jobs: u32,
    pub rating_sum: u64,
    pub created_at: u64,
}

/// A single reviewer-signed review of a completed job. Not yet written by any
/// function — `submit_review` (Phase 2) is what will construct and store these.
#[contracttype]
#[derive(Clone)]
pub struct Review {
    pub worker: Address,
    pub reviewer: Address,
    pub job_id: Symbol,
    pub rating: u32,
    pub timestamp: u64,
}

#[contracttype]
#[derive(Clone)]
pub enum DataKey {
    /// -> WorkerProfile
    Worker(Address),
    /// -> Review, keyed by (worker, job_id) — enforces "one review per job"
    Review(Address, Symbol),
    /// -> Vec<Symbol>, ordered job_ids for a worker, for get_reviews pagination
    ReviewIds(Address),
}

/// Only `AlreadyRegistered` is reachable in Phase 1. The rest of the error set
/// (NotRegistered, InvalidRating, DuplicateReview, SelfReview) lands in Phase 2
/// alongside the functions that can actually trigger them — adding them now,
/// unused, would just be dead code with no test able to exercise it yet.
#[contracterror]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
#[repr(u32)]
pub enum Error {
    AlreadyRegistered = 1,
}

#[contractevent]
pub struct WorkerRegistered {
    #[topic]
    pub worker: Address,
    pub timestamp: u64,
}

#[contract]
pub struct ReputationContract;

#[contractimpl]
impl ReputationContract {
    /// Worker registers themself. Must be signed by `worker`.
    ///
    /// Calling this twice for the same address returns `AlreadyRegistered`
    /// rather than silently no-op'ing: a worker's `total_jobs`/`rating_sum`
    /// are only ever supposed to move forward via `submit_review`, so a
    /// second `register_worker` call is either a caller bug or an attempt to
    /// reset an existing history — both should be loud, not silent.
    pub fn register_worker(env: Env, worker: Address) -> Result<(), Error> {
        worker.require_auth();

        let key = DataKey::Worker(worker.clone());
        if env.storage().persistent().has(&key) {
            return Err(Error::AlreadyRegistered);
        }

        let created_at = env.ledger().timestamp();
        let profile = WorkerProfile {
            total_jobs: 0,
            rating_sum: 0,
            created_at,
        };
        env.storage().persistent().set(&key, &profile);

        WorkerRegistered {
            worker,
            timestamp: created_at,
        }
        .publish(&env);

        Ok(())
    }
}

mod test;
