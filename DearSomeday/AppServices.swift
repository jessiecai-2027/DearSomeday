//
//  AppServices.swift
//  DearSomeday
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
import UserNotifications

@MainActor
final class AppServices {

    let store: PostcardStore
    let photoStore: PhotoStore
    let clock: TrustedClock
    let lifecycle: PostcardLifecycle
    let coordinator: UnlockCoordinator
    let creationService: PostcardCreationService
    let notificationScheduler: NotificationScheduler
    let notificationRouter: NotificationRouter

    /// Retained so it stays alive as the notification-center delegate (the
    /// center holds it weakly).
    private let notificationDelegate: NotificationDelegate

    init(container: ModelContainer) throws {
        let clock = TrustedClock(uptime: { ProcessInfo.processInfo.systemUptime })
        let store = SwiftDataPostcardStore(container: container)
        let lifecycle = PostcardLifecycle(clock: clock)
        let photoStore = try FileSystemPhotoStore.applicationSupport()

        let router = NotificationRouter()
        let delegate = NotificationDelegate(router: router)
        UNUserNotificationCenter.current().delegate = delegate

        self.clock = clock
        self.store = store
        self.photoStore = photoStore
        self.lifecycle = lifecycle
        self.coordinator = UnlockCoordinator(store: store, lifecycle: lifecycle, clock: clock)
        self.creationService = PostcardCreationService(
            store: store,
            photoStore: photoStore,
            lifecycle: lifecycle,
            clock: clock
        )
        self.notificationScheduler = NotificationScheduler()
        self.notificationRouter = router
        self.notificationDelegate = delegate
    }
}
