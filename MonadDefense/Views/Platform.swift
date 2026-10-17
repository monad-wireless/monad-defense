import SwiftUI
import UIKit

// MARK: - The one place that asks which device this is
//
// The app is one SwiftUI target for iPhone, iPad and Mac (Catalyst, Mac idiom).
// A view branches on what the reader can DO, not on the device name: a Mac has
// no pull-to-refresh and no swipe, but it has a keyboard and a pointer. Keep
// those questions here so a branch is a word, not a `UIDevice` call.

enum Platform {
    /// Catalyst with the Mac idiom: a pointer, a keyboard, a resizable window.
    @MainActor static var isMac: Bool { UIDevice.current.userInterfaceIdiom == .mac }

    /// Width of a column of reading text. `PaperView` and `ClaimView` set the
    /// same 720; a wide window otherwise runs a serif line past 200 characters.
    static let readingWidth: CGFloat = 720
}

extension View {
    /// Centre the content in a column no wider than a comfortable line.
    func readingColumn(_ width: CGFloat = Platform.readingWidth) -> some View {
        frame(maxWidth: width).frame(maxWidth: .infinity)
    }

    /// A keyboard shortcut that only exists where a keyboard is the main input.
    /// On a phone a bare-letter shortcut would fire from a paired keyboard
    /// nobody expects to be live, so it stays off there.
    /// Nil means no key: an MCQ's tenth option has no digit.
    @ViewBuilder
    func macShortcut(_ key: KeyEquivalent?, modifiers: EventModifiers = []) -> some View {
        if Platform.isMac, let key {
            keyboardShortcut(key, modifiers: modifiers)
        } else {
            self
        }
    }
}

// MARK: - Window

enum MacWindow {
    /// Below this the sidebar, the card and the legend stop fitting side by side.
    static let minimumSize = CGSize(width: 820, height: 620)

    /// Catalyst windows default to a phone-shaped minimum. Called once the
    /// first scene is connected; a no-op on iPhone and iPad.
    @MainActor static func configure() {
        #if targetEnvironment(macCatalyst)
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            scene.sizeRestrictions?.minimumSize = minimumSize
            scene.title = "Defense"
        }
        #endif
    }
}

// MARK: - Key hints

/// A small key cap, for the legends that tell a Mac reader which key does what.
struct KeyCap: View {
    let key: String

    init(_ key: String) { self.key = key }

    var body: some View {
        Text(key)
            .font(.caption2.monospaced().weight(.semibold))
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(.quaternary, in: .rect(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(.tertiary, lineWidth: 0.5))
    }
}
