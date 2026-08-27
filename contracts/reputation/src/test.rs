#![cfg(test)]

use super::*;
use soroban_sdk::testutils::Address as _;
use soroban_sdk::Env;

fn setup() -> (Env, ReputationContractClient<'static>, Address) {
    let env = Env::default();
    env.mock_all_auths();
    let contract_id = env.register(ReputationContract, ());
    let client = ReputationContractClient::new(&env, &contract_id);
    let worker = Address::generate(&env);
    (env, client, worker)
}

/// Seeds a registered WorkerProfile directly in storage, bypassing
/// register_worker's own auth requirement — for tests that are only
/// exercising submit_review/get_reputation/get_reviews behavior.
fn seed_worker(env: &Env, contract_id: &Address, worker: &Address) {
    env.as_contract(contract_id, || {
        env.storage().persistent().set(
            &DataKey::Worker(worker.clone()),
            &WorkerProfile {
                total_jobs: 0,
                rating_sum: 0,
                created_at: 0,
            },
        );
    });
}

// -- register_worker --------------------------------------------------

#[test]
fn register_worker_succeeds_on_first_call() {
    let (env, client, worker) = setup();

    client.register_worker(&worker);

    let profile = env.as_contract(&client.address, || {
        env.storage()
            .persistent()
            .get::<_, WorkerProfile>(&DataKey::Worker(worker.clone()))
            .unwrap()
    });
    assert_eq!(profile.total_jobs, 0);
    assert_eq!(profile.rating_sum, 0);
    assert_eq!(profile.created_at, env.ledger().timestamp());
}

#[test]
fn register_worker_rejects_second_registration() {
    let (_env, client, worker) = setup();

    client.register_worker(&worker);
    let result = client.try_register_worker(&worker);

    assert_eq!(result, Err(Ok(Error::AlreadyRegistered)));
}

#[test]
fn register_worker_requires_worker_auth() {
    let env = Env::default();
    // Deliberately not calling mock_all_auths() — this test verifies
    // require_auth() is actually enforced, not just that it compiles.
    let contract_id = env.register(ReputationContract, ());
    let client = ReputationContractClient::new(&env, &contract_id);
    let worker = Address::generate(&env);

    let result = client.try_register_worker(&worker);

    assert!(result.is_err());
}

// -- submit_review -------------------------------------------------------

#[test]
fn submit_review_succeeds_and_updates_profile() {
    let (env, client, worker) = setup();
    let reviewer = Address::generate(&env);
    client.register_worker(&worker);

    client.submit_review(&worker, &reviewer, &Symbol::new(&env, "job1"), &4);
    client.submit_review(&worker, &reviewer, &Symbol::new(&env, "job2"), &5);

    let profile = client.get_reputation(&worker);
    assert_eq!(profile.total_jobs, 2);
    assert_eq!(profile.rating_sum, 9);
}

#[test]
fn submit_review_returns_not_registered() {
    let (env, client, worker) = setup();
    let reviewer = Address::generate(&env);

    let result = client.try_submit_review(&worker, &reviewer, &Symbol::new(&env, "job1"), &5);

    assert_eq!(result, Err(Ok(Error::NotRegistered)));
}

#[test]
fn submit_review_returns_self_review() {
    let (env, client, worker) = setup();
    client.register_worker(&worker);

    let result = client.try_submit_review(&worker, &worker, &Symbol::new(&env, "job1"), &5);

    assert_eq!(result, Err(Ok(Error::SelfReview)));
}

#[test]
fn submit_review_returns_invalid_rating_for_zero() {
    let (env, client, worker) = setup();
    let reviewer = Address::generate(&env);
    client.register_worker(&worker);

    let result = client.try_submit_review(&worker, &reviewer, &Symbol::new(&env, "job1"), &0);

    assert_eq!(result, Err(Ok(Error::InvalidRating)));
}

#[test]
fn submit_review_returns_invalid_rating_for_six() {
    let (env, client, worker) = setup();
    let reviewer = Address::generate(&env);
    client.register_worker(&worker);

    let result = client.try_submit_review(&worker, &reviewer, &Symbol::new(&env, "job1"), &6);

    assert_eq!(result, Err(Ok(Error::InvalidRating)));
}

#[test]
fn submit_review_returns_duplicate_review() {
    let (env, client, worker) = setup();
    let reviewer = Address::generate(&env);
    client.register_worker(&worker);
    client.submit_review(&worker, &reviewer, &Symbol::new(&env, "job1"), &5);

    let result = client.try_submit_review(&worker, &reviewer, &Symbol::new(&env, "job1"), &3);

    assert_eq!(result, Err(Ok(Error::DuplicateReview)));
}

#[test]
fn submit_review_requires_reviewer_auth() {
    let env = Env::default();
    // No mock_all_auths() here — seed the registered worker directly so
    // this test is purely about submit_review's own auth requirement,
    // not entangled with register_worker's.
    let contract_id = env.register(ReputationContract, ());
    let client = ReputationContractClient::new(&env, &contract_id);
    let worker = Address::generate(&env);
    let reviewer = Address::generate(&env);
    seed_worker(&env, &contract_id, &worker);

    let result = client.try_submit_review(&worker, &reviewer, &Symbol::new(&env, "job1"), &5);

    assert!(result.is_err());
}

// -- get_reputation --------------------------------------------------------

#[test]
fn get_reputation_returns_not_registered_for_unknown_address() {
    let (_env, client, worker) = setup();

    let result = client.try_get_reputation(&worker);

    assert_eq!(result, Err(Ok(Error::NotRegistered)));
}

// -- get_reviews (pagination) ------------------------------------------

#[test]
fn get_reviews_paginates_from_start() {
    let (env, client, worker) = setup();
    let reviewer = Address::generate(&env);
    client.register_worker(&worker);
    client.submit_review(&worker, &reviewer, &Symbol::new(&env, "job1"), &1);
    client.submit_review(&worker, &reviewer, &Symbol::new(&env, "job2"), &2);
    client.submit_review(&worker, &reviewer, &Symbol::new(&env, "job3"), &3);

    let page = client.get_reviews(&worker, &0, &2);

    assert_eq!(page.len(), 2);
    assert_eq!(page.get(0).unwrap().job_id, Symbol::new(&env, "job1"));
    assert_eq!(page.get(1).unwrap().job_id, Symbol::new(&env, "job2"));
}

#[test]
fn get_reviews_returns_empty_when_start_beyond_length() {
    let (env, client, worker) = setup();
    let reviewer = Address::generate(&env);
    client.register_worker(&worker);
    client.submit_review(&worker, &reviewer, &Symbol::new(&env, "job1"), &1);

    let page = client.get_reviews(&worker, &10, &5);

    assert_eq!(page.len(), 0);
}

#[test]
fn get_reviews_clamps_limit_larger_than_remaining() {
    let (env, client, worker) = setup();
    let reviewer = Address::generate(&env);
    client.register_worker(&worker);
    client.submit_review(&worker, &reviewer, &Symbol::new(&env, "job1"), &1);
    client.submit_review(&worker, &reviewer, &Symbol::new(&env, "job2"), &2);

    let page = client.get_reviews(&worker, &1, &100);

    assert_eq!(page.len(), 1);
    assert_eq!(page.get(0).unwrap().job_id, Symbol::new(&env, "job2"));
}

#[test]
fn get_reviews_returns_empty_for_worker_with_no_reviews() {
    let (_env, client, worker) = setup();
    client.register_worker(&worker);

    let page = client.get_reviews(&worker, &0, &10);

    assert_eq!(page.len(), 0);
}
