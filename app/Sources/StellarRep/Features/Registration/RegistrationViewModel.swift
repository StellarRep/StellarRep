import Foundation
import stellarsdk

/// Drives registering a wallet as a worker with the reputation contract —
/// the first real contract call in the app, and the concrete demonstration
/// of the pending/failed pattern `docs/APP_SPEC.md`/`docs/ROADMAP.md` Phase 5
/// calls for. No View yet: Phase 6 ("Core UI Flows") wires this into the
/// actual registration screen; this phase is about the service layer and
/// the state-handling pattern being real, not about the screen.
@MainActor
public final class RegistrationViewModel: ObservableObject {
    @Published public private(set) var state: ContractCallState<EmptySuccess> = .idle

    private let service: ReputationServiceProtocol

    public init(service: ReputationServiceProtocol = ReputationService()) {
        self.service = service
    }

    public func register(signer: KeyPair) async {
        state = .pending
        do {
            try await service.registerWorker(signer: signer)
            state = .succeeded(EmptySuccess())
        } catch let error as ReputationServiceError {
            state = .failed(error)
        } catch {
            state = .failed(.network(String(describing: error)))
        }
    }
}
