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
    /// The timeline (task B) reads through a `SwiftDataPostcardStore` over this.
    private let modelContainer: ModelContainer

    init() {
        do {
            modelContainer = try SwiftDataPostcardStore.makeContainer()
        } catch {
            fatalError("Failed to open the postcard store: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(modelContainer)
    }
}
