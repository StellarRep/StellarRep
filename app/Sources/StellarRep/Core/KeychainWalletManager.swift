import Foundation
import Security
import stellarsdk

/// Errors raised by `KeychainWalletManager`.
enum KeychainWalletError: Error, Equatable {
    /// A wallet already exists in the Keychain; call `deleteWallet()` first
    /// if the intent is really to replace it.
    case walletAlreadyExists
    /// No wallet has been created or imported yet.
    case noWalletFound
    /// The provided secret seed isn't a valid Stellar secret key.
    case invalidSecretSeed
    /// The underlying Keychain call failed; carries the raw `OSStatus`.
    case keychainFailure(OSStatus)
}

/// Owns the single wallet keypair this app manages, backed by Keychain.
///
/// The secret key never touches `UserDefaults`, a plist, or any plaintext
/// file — it lives only in the iOS Keychain (`kSecClassGenericPassword`),
/// per CLAUDE.md/APP_SPEC.md. This class stores and retrieves the secret
/// seed string; reconstructing a `KeyPair` from it is the caller's job via
/// `stellarsdk`'s own `KeyPair(secretSeed:)`, so this type has zero
/// crypto logic of its own to get wrong.
final class KeychainWalletManager: Sendable {
    private let service: String
    private let account = "stellarrep-wallet-secret-seed"

    /// `service` defaults to the app's bundle identifier so multiple apps on
    /// the same device (or, in tests, multiple manager instances) don't
    /// collide in the same Keychain namespace. Tests pass a unique value per
    /// run instead, so parallel/leftover test runs can't see each other's
    /// wallets.
    init(service: String = Bundle.main.bundleIdentifier ?? "com.stellarrep.app") {
        self.service = service
    }

    var hasWallet: Bool {
        (try? loadSecretSeed()) != nil
    }

    /// Generates a brand-new keypair and stores its secret seed in the
    /// Keychain. Fails with `.walletAlreadyExists` rather than silently
    /// overwriting — same reasoning as the contract's `register_worker`:
    /// destroying an existing wallet's key should never be a side effect of
    /// the "create new" path.
    func generateNewWallet() throws -> KeyPair {
        guard !hasWallet else { throw KeychainWalletError.walletAlreadyExists }
        let keyPair = try KeyPair.generateRandomKeyPair()
        guard let secretSeed = keyPair.secretSeed else {
            // Unreachable in practice: a freshly generated KeyPair always
            // carries a private key, and secretSeed is only nil for a
            // public-key-only KeyPair. Guarded rather than force-unwrapped
            // because "the SDK changed its invariants" should fail loudly,
            // not crash.
            throw KeychainWalletError.invalidSecretSeed
        }
        try store(secretSeed: secretSeed)
        return keyPair
    }

    /// Imports an existing wallet from its secret seed (starts with `S`).
    /// Validates the seed by actually constructing a `KeyPair` from it
    /// before storing anything, so a typo never lands a garbage value in
    /// the Keychain.
    func importWallet(secretSeed: String) throws -> KeyPair {
        guard !hasWallet else { throw KeychainWalletError.walletAlreadyExists }
        let keyPair: KeyPair
        do {
            keyPair = try KeyPair(secretSeed: secretSeed)
        } catch {
            throw KeychainWalletError.invalidSecretSeed
        }
        try store(secretSeed: secretSeed)
        return keyPair
    }

    /// Loads the previously created/imported wallet, or throws
    /// `.noWalletFound` if none exists yet.
    func loadWallet() throws -> KeyPair {
        guard let secretSeed = try loadSecretSeed() else {
            throw KeychainWalletError.noWalletFound
        }
        return try KeyPair(secretSeed: secretSeed)
    }

    /// Removes the stored wallet. Used by tests to reset state, and by the
    /// app itself only behind an explicit, deliberate user action (never
    /// automatically) — see Settings in `docs/APP_SPEC.md`.
    func deleteWallet() throws {
        let query = baseQuery()
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainWalletError.keychainFailure(status)
        }
    }

    // MARK: - Keychain plumbing

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    private func store(secretSeed: String) throws {
        var query = baseQuery()
        query[kSecValueData as String] = Data(secretSeed.utf8)
        // Accessible as soon as the device is unlocked once after boot, and
        // never synced to iCloud Keychain or another device — a wallet
        // secret is device-local by design.
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainWalletError.keychainFailure(status)
        }
    }

    private func loadSecretSeed() throws -> String? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            guard let data = result as? Data, let seed = String(data: data, encoding: .utf8) else {
                throw KeychainWalletError.keychainFailure(status)
            }
            return seed
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainWalletError.keychainFailure(status)
        }
    }
}
