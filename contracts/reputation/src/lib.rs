#![no_std]
use soroban_sdk::{
    contract, contracterror, contractevent, contractimpl, contracttype, Address, Env, Symbol, Vec,
};

/// A worker's aggregate on-chain reputation. `average = rating_sum / total_jobs`
/// (computed by callers — division is left out of storage to avoid lossy writes).
#[contracttype]
#[derive(Clone, Debug, PartialEq)]
pub struct WorkerProfile {
    pub total_jobs: u32,
    pub rating_sum: u64,
    pub created_at: u64,
}

/// A single reviewer-signed review of a completed job.
#[contracttype]
#[derive(Clone, Debug, PartialEq)]
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

#[contracterror]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
#[repr(u32)]
pub enum Error {
    AlreadyRegistered = 1,
    NotRegistered = 2,
    InvalidRating = 3,
    DuplicateReview = 4,
    SelfReview = 5,
}

#[contractevent]
pub struct WorkerRegistered {
    #[topic]
    pub worker: Address,
    pub timestamp: u64,
}

#[contractevent]
pub struct ReviewSubmitted {
    #[topic]
    pub worker: Address,
    pub reviewer: Address,
    pub job_id: Symbol,
    pub rating: u32,
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
        Self::bump_ttl(&env, &key);

        WorkerRegistered {
            worker,
            timestamp: created_at,
        }
        .publish(&env);

        Ok(())
    }

    /// Reviewer submits a review for a worker's completed job. Must be
    /// signed by `reviewer`, NOT `worker` — a worker can't review themself
    /// into a good rating.
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
        if !(1..=5).contains(&rating) {
            return Err(Error::InvalidRating);
        }

        let worker_key = DataKey::Worker(worker.clone());
        let mut profile: WorkerProfile = env
            .storage()
            .persistent()
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
        Self::bump_ttl(&env, &review_key);

        let ids_key = DataKey::ReviewIds(worker.clone());
        let mut ids: Vec<Symbol> = env
            .storage()
            .persistent()
            .get(&ids_key)
            .unwrap_or_else(|| Vec::new(&env));
        ids.push_back(job_id.clone());
        env.storage().persistent().set(&ids_key, &ids);
        Self::bump_ttl(&env, &ids_key);

        profile.total_jobs += 1;
        profile.rating_sum += rating as u64;
        env.storage().persistent().set(&worker_key, &profile);
        Self::bump_ttl(&env, &worker_key);

        ReviewSubmitted {
            worker,
            reviewer,
            job_id,
            rating,
        }
        .publish(&env);

        Ok(())
    }

    /// Read-only. No auth required.
    pub fn get_reputation(env: Env, worker: Address) -> Result<WorkerProfile, Error> {
        env.storage()
            .persistent()
            .get(&DataKey::Worker(worker))
            .ok_or(Error::NotRegistered)
    }

    /// Read-only, paginated. No auth required. An unregistered worker (or one
    /// with no reviews yet) simply returns an empty list rather than an
    /// error — pagination over nothing is a valid, boring case, not a fault.
    pub fn get_reviews(env: Env, worker: Address, start: u32, limit: u32) -> Vec<Review> {
        let ids: Vec<Symbol> = env
            .storage()
            .persistent()
            .get(&DataKey::ReviewIds(worker.clone()))
            .unwrap_or_else(|| Vec::new(&env));

        let len = ids.len();
        let start = start.min(len);
        let end = start.saturating_add(limit).min(len);

        let mut reviews = Vec::new(&env);
        for i in start..end {
            let job_id = ids.get_unchecked(i);
            if let Some(review) = env
                .storage()
                .persistent()
                .get::<_, Review>(&DataKey::Review(worker.clone(), job_id))
            {
                reviews.push_back(review);
            }
        }
        reviews
    }

    /// Extends a persistent entry's TTL to the network's current maximum
    /// once it drops below half that maximum, rather than on every single
    /// touch — cheap in the common case, and never lets an entry that's
    /// still being actively used (registered worker, ongoing review
    /// history) drift into archival. `max_ttl()` is read from the network
    /// live rather than hardcoded, since the allowed maximum is a network
    /// parameter that can change between protocol versions.
    fn bump_ttl(env: &Env, key: &DataKey) {
        let max_ttl = env.storage().max_ttl();
        env.storage()
            .persistent()
            .extend_ttl(key, max_ttl / 2, max_ttl);
    }
}

mod test;
