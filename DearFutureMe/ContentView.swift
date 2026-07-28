//
//  ContentView.swift
//  DearFutureMe
//
//  Token test screen: every colour token as a labelled swatch, every font
//  token rendering sample text. Plain layout, works in light and dark mode.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tokens.Space.xl) {

                Text("Design Tokens")
                    .font(Tokens.Font.screenTitle)
                    .foregroundStyle(Tokens.Color.chromeText)

                // MARK: Colour tokens

                Group {
                    sectionHeader("Canvas colours (fixed)")
                    swatch("paperCream",  Tokens.Color.paperCream)
                    swatch("paperTan",    Tokens.Color.paperTan)
                    swatch("paperTaupe",  Tokens.Color.paperTaupe)
                    swatch("accentSage",  Tokens.Color.accentSage)
                    swatch("inkEspresso", Tokens.Color.inkEspresso)
                }

                Group {
                    sectionHeader("Chrome colours (adaptive)")
                    swatch("chromeBackground", Tokens.Color.chromeBackground)
                    swatch("chromeSurface",    Tokens.Color.chromeSurface)
                    swatch("chromeText",       Tokens.Color.chromeText)
                    swatch("chromeTextMuted",  Tokens.Color.chromeTextMuted)
                    swatch("chromeDivider",    Tokens.Color.chromeDivider)
                    swatch("chromeAccent",     Tokens.Color.chromeAccent)
                    swatch("danger",           Tokens.Color.danger)
                }

                // MARK: Font tokens

                Group {
                    sectionHeader("Chrome fonts")
                    fontSample("screenTitle",  Tokens.Font.screenTitle)
                    fontSample("sectionLabel", Tokens.Font.sectionLabel)
                    fontSample("body",         Tokens.Font.body)
                    fontSample("caption",      Tokens.Font.caption)
                    fontSample("button",       Tokens.Font.button)
                }

                Group {
                    sectionHeader("Canvas fonts")
                    fontSample("cardTitle",   Tokens.Font.cardTitle)
                    fontSample("cardBody",    Tokens.Font.cardBody)
                    fontSample("handwriting", Tokens.Font.handwriting)
                    fontSample("stamp",       Tokens.Font.stamp)
                }
            }
            .padding(Tokens.Space.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Tokens.Color.chromeBackground)
    }

    // MARK: Builders

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(Tokens.Font.sectionLabel)
            .tracking(Tokens.Font.Tracking.sectionLabel)
            .foregroundStyle(Tokens.Color.chromeTextMuted)
    }

    private func swatch(_ name: String, _ color: Color) -> some View {
        HStack(spacing: Tokens.Space.md) {
            RoundedRectangle(cornerRadius: Tokens.Radius.subtle)
                .fill(color)
                .frame(width: 56, height: 56)
                .overlay(
                    RoundedRectangle(cornerRadius: Tokens.Radius.subtle)
                        .stroke(Tokens.Color.chromeDivider, lineWidth: 1)
                )
            Text(name)
                .font(Tokens.Font.body)
                .foregroundStyle(Tokens.Color.chromeText)
        }
    }

    private func fontSample(_ name: String, _ font: Font) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Space.xxs) {
            Text(name)
                .font(Tokens.Font.caption)
                .foregroundStyle(Tokens.Color.chromeTextMuted)
            Text("The quick brown fox jumps over the lazy dog")
                .font(font)
                .foregroundStyle(Tokens.Color.chromeText)
        }
    }
}

#Preview {
    ContentView()
}
