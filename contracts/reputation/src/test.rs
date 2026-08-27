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
