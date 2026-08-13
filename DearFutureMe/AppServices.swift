//
//  AppServices.swift
//  DearFutureMe
//
//  The composition root: builds the one instance of each foundation layer and
//  wires them together, so views receive ready-made collaborators instead of
//  constructing (and mis-wiring) their own. Constructed once at launch.
//
//  The single shared `TrustedClock` is deliberate — the lifecycle and the
//  coordinator must read the *same* trusted time, or a card could evaluate
//  against a clock the sweep hasn't synced. One clock, injected into both.
//

import Foundation
import SwiftData

@MainActor
final class AppServices {

    let store: PostcardStore
    let photoStore: PhotoStore
    let clock: TrustedClock
    let lifecycle: PostcardLifecycle
    let coordinator: UnlockCoordinator

    init(container: ModelContainer) throws {
        let clock = TrustedClock(uptime: { ProcessInfo.processInfo.systemUptime })
        let store = SwiftDataPostcardStore(container: container)
        let lifecycle = PostcardLifecycle(clock: clock)

        self.clock = clock
        self.store = store
        self.photoStore = try FileSystemPhotoStore.applicationSupport()
        self.lifecycle = lifecycle
        self.coordinator = UnlockCoordinator(store: store, lifecycle: lifecycle, clock: clock)
    }
}
