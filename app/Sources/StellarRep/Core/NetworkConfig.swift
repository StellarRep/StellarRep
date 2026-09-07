import stellarsdk

/// Single source of truth for which Stellar network this app talks to.
///
/// Per CLAUDE.md ground rule 1: testnet only until told otherwise. Nothing
/// else in this codebase should hardcode a Horizon/RPC URL or a network
/// passphrase — route through here so a future mainnet decision (if it ever
/// happens) is a one-file change, not a grep-and-replace.
public enum NetworkConfig {
    /// Always true for this build. Gates anything that must never run
    /// against a real network — e.g. Friendbot funding.
    public static let isTestnet = true

    public static let horizonURL = StellarSDK.testNetUrl
    public static let sorobanRPCURL = "https://soroban-testnet.stellar.org"
    public static let networkPassphrase = Network.testnet.passphrase

    public static let sdk = StellarSDK(withHorizonUrl: horizonURL)

    /// The `reputation` contract's deployed testnet instance — see
    /// `contracts/reputation/DEPLOYED.md` for the tx hashes and manual
    /// verification that back this ID.
    public static let reputationContractId = "CASDNMYRVVFRTCS23GK2M77VP3W2YCB6NXKT33KL5ZIX6VW4W4TYEPOM"
}

extension HorizonRequestError {
    /// Every case of this SDK error carries its own `message`; surfacing it
    /// directly reads far better than the generic NSError-bridged text
    /// `localizedDescription` would otherwise produce.
    var message: String {
        switch self {
        case .requestFailed(let message, _), .badRequest(let message, _),
             .unauthorized(let message), .forbidden(let message, _),
             .notFound(let message, _), .notAcceptable(let message, _),
             .duplicate(let message, _), .beforeHistory(let message, _),
             .payloadTooLarge(let message, _), .rateLimitExceeded(let message, _),
             .internalServerError(let message, _), .notImplemented(let message, _),
             .staleHistory(let message, _), .timeout(let message, _):
            return message
        default:
            return String(describing: self)
        }
    }
}
