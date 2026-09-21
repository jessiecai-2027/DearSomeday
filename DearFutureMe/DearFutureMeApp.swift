//
//  DearFutureMeApp.swift
//  DearFutureMe
//
//  Created by Jessie Cai on 7/28/26.
//

import SwiftUI
import SwiftData
import UIKit
import CoreText

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
        if let fontURL = Bundle.main.url(forResource: "BodoniModa_9pt-Regular", withExtension: "ttf") {
            CTFontManagerRegisterFontsForURL(fontURL as CFURL, .process, nil)
        }

        let chromeTextColor = UIColor(red: 58 / 255, green: 48 / 255, blue: 42 / 255, alpha: 1)
        let titleFont = UIFont(name: "BodoniModa9pt-Regular", size: 17) ?? .systemFont(ofSize: 17, weight: .semibold)
        let largeTitleFont = UIFont(name: "BodoniModa9pt-Regular", size: 34) ?? .systemFont(ofSize: 34, weight: .semibold)
        let titleShadow = NSShadow()
        titleShadow.shadowColor = chromeTextColor.withAlphaComponent(0.22)
        titleShadow.shadowBlurRadius = 1.25
        titleShadow.shadowOffset = CGSize(width: 0, height: 1)
        let navigationTitleAttributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: chromeTextColor,
            .font: titleFont,
            .shadow: titleShadow
        ]
        let navigationLargeTitleAttributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: chromeTextColor,
            .font: largeTitleFont,
            .shadow: titleShadow
        ]
        let navigationAppearance = UINavigationBarAppearance()
        navigationAppearance.configureWithTransparentBackground()
        navigationAppearance.backgroundColor = .clear
        navigationAppearance.shadowColor = .clear
        navigationAppearance.titleTextAttributes = navigationTitleAttributes
        navigationAppearance.largeTitleTextAttributes = navigationLargeTitleAttributes

        UINavigationBar.appearance().standardAppearance = navigationAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navigationAppearance
        UINavigationBar.appearance().compactAppearance = navigationAppearance
        UINavigationBar.appearance().titleTextAttributes = navigationTitleAttributes
        UINavigationBar.appearance().largeTitleTextAttributes = navigationLargeTitleAttributes

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
                .appBackground()
            .font(Tokens.Font.body)
            .foregroundStyle(Tokens.Color.chromeText)
            .tint(Tokens.Color.chromeText)
        }
        .modelContainer(modelContainer)
    }
}
