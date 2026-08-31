import StellarRep
import SwiftUI

/// App entry point, deliberately kept in its own target rather than inside
/// `StellarRep` itself: SwiftPM links a library target's `@main` type into
/// anything that depends on it, including the test target — so `@main`
/// living in `StellarRep` broke `swift test` with a duplicate `_main` symbol
/// the moment `StellarRepTests` (which depends on `StellarRep`) tried to
/// link. This target has no dependents of its own, so it can't collide.
///
/// This is an SPM-first package (see the Phase 0 decision in
/// `docs/APP_SPEC.md`) — there is no `.xcodeproj`. Opening `app/` directly
/// in Xcode treats `Package.swift` as an implicit project and can run this
/// target on Simulator like a normal app.
@main
struct StellarRepApp: App {
    var body: some Scene {
        WindowGroup {
            OnboardingView()
        }
    }
}
