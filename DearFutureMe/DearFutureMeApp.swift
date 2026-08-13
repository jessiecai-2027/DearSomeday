//
//  DearFutureMeApp.swift
//  DearFutureMe
//
//  Created by Jessie Cai on 7/28/26.
//

import SwiftUI
import SwiftData

@main
struct DearFutureMeApp: App {

    /// The local SwiftData store, opened once at launch. A container that can't
    /// open is unrecoverable (corrupt store / no disk) and there is nothing the
    /// user could do in-app about it, so we fail fast rather than run storeless.
    private let modelContainer: ModelContainer

    /// The composition root — store, trusted clock, lifecycle, unlock sweep —
    /// built once over the container above.
    private let services: AppServices

    init() {
        do {
            let container = try SwiftDataPostcardStore.makeContainer()
            self.modelContainer = container
            self.services = try AppServices(container: container)
        } catch {
            fatalError("Failed to start the app: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            PostcardTimelineView(services: services)
        }
        .modelContainer(modelContainer)
    }
}
