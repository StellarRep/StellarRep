/// Stand-in for a contract call that returns no meaningful value
/// (`register_worker`, `submit_review`), so `ContractCallState` can stay one
/// generic type instead of needing a separate non-generic enum for the
/// void-returning cases.
public struct EmptySuccess: Equatable, Sendable {
    public init() {}
}

/// The lifecycle of a single contract call, from a ViewModel's perspective.
///
/// Per `docs/APP_SPEC.md`: pending and failed must read differently to the
/// user, and a failure must distinguish "the contract rejected this"
/// (`ReputationServiceError.contract`, a specific reason the user can be
/// told directly — see `ReputationService.run(_:)`) from "something about
/// reaching it failed" (`.network`). Every ViewModel that calls into
/// `ReputationServiceProtocol` should drive its UI off one of these rather
/// than collapsing pending/failed/succeeded into a boolean or optional.
public enum ContractCallState<Success: Equatable & Sendable>: Equatable, Sendable {
    case idle
    case pending
    case succeeded(Success)
    case failed(ReputationServiceError)
}
