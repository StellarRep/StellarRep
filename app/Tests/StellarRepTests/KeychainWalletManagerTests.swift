import Foundation
import Testing
import stellarsdk
@testable import StellarRep

/// Exercises the real Keychain (no mocking — there's nothing to mock here,
/// this class *is* the thin Keychain wrapper). Each instance gets its own
/// `service` namespace so parallel/leftover runs can't see each other's
/// wallets, and cleans up after itself in `deinit`.
@Suite
final class KeychainWalletManagerTests {
    let sut = KeychainWalletManager(service: "com.stellarrep.tests.\(UUID().uuidString)")

    deinit {
        try? sut.deleteWallet()
    }

    @Test func generateNewWalletSucceedsAndPersists() throws {
        let generated = try sut.generateNewWallet()

        #expect(sut.hasWallet)
        let loaded = try sut.loadWallet()
        #expect(loaded.accountId == generated.accountId)
        #expect(loaded.secretSeed == generated.secretSeed)
    }

    @Test func generateNewWalletTwiceThrowsAlreadyExists() throws {
        _ = try sut.generateNewWallet()

        do {
            _ = try sut.generateNewWallet()
            Issue.record("expected generateNewWallet() to throw")
        } catch {
            #expect(error as? KeychainWalletError == .walletAlreadyExists)
        }
    }

    @Test func importWalletSucceedsWithValidSeed() throws {
        let source = try KeyPair.generateRandomKeyPair()

        let imported = try sut.importWallet(secretSeed: source.secretSeed!)

        #expect(imported.accountId == source.accountId)
        #expect(try sut.loadWallet().accountId == source.accountId)
    }

    @Test func importWalletRejectsInvalidSeed() {
        do {
            _ = try sut.importWallet(secretSeed: "not-a-real-seed")
            Issue.record("expected importWallet(secretSeed:) to throw")
        } catch {
            #expect(error as? KeychainWalletError == .invalidSecretSeed)
        }
        #expect(!sut.hasWallet)
    }

    @Test func importWalletTwiceThrowsAlreadyExists() throws {
        let first = try KeyPair.generateRandomKeyPair()
        _ = try sut.importWallet(secretSeed: first.secretSeed!)
        let second = try KeyPair.generateRandomKeyPair()

        do {
            _ = try sut.importWallet(secretSeed: second.secretSeed!)
            Issue.record("expected importWallet(secretSeed:) to throw")
        } catch {
            #expect(error as? KeychainWalletError == .walletAlreadyExists)
        }
    }

    @Test func loadWalletThrowsNoWalletFoundWhenEmpty() {
        #expect(!sut.hasWallet)
        do {
            _ = try sut.loadWallet()
            Issue.record("expected loadWallet() to throw")
        } catch {
            #expect(error as? KeychainWalletError == .noWalletFound)
        }
    }

    @Test func deleteWalletRemovesIt() throws {
        _ = try sut.generateNewWallet()
        #expect(sut.hasWallet)

        try sut.deleteWallet()

        #expect(!sut.hasWallet)
    }

    @Test func deleteWalletIsIdempotentWhenNothingStored() throws {
        try sut.deleteWallet()
    }
}
