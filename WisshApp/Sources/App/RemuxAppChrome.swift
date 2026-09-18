import SwiftUI
import UIKit

enum RemuxAppPalette {
    static let background = Color(uiColor: .remuxAppBackground)
    static let rowSurface = Color(uiColor: .remuxAppRowSurface)
    static let separator = Color(uiColor: .remuxAppSeparator)
    static let sectionHeader = Color(uiColor: .remuxAppSectionHeader)
    static let toolbarTint = Color(uiColor: .remuxAppToolbarTint)
    static let controlAccent = Color(uiColor: .remuxAppControlAccent)
    static let rowIconForeground = Color(uiColor: .remuxAppRowIconForeground)
    static let rowIconSurface = Color(uiColor: .remuxAppRowIconSurface)
}

typealias LibraryHomePalette = RemuxAppPalette

extension TerminalTheme {
    var remuxAppColorScheme: ColorScheme {
        switch self {
        case .remuxLight:
            .light
        case .ghosttyDefault, .remuxDark:
            .dark
        }
    }

    var libraryColorScheme: ColorScheme {
        remuxAppColorScheme
    }
}

extension View {
    func remuxAppListRowSurface() -> some View {
        listRowBackground(RemuxAppPalette.rowSurface)
            .listRowSeparatorTint(RemuxAppPalette.separator)
    }

    func remuxAppChrome(theme: TerminalTheme) -> some View {
        preferredColorScheme(theme.remuxAppColorScheme)
            .tint(RemuxAppPalette.toolbarTint)
            .toolbarBackground(RemuxAppPalette.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
    }

    func remuxAppGroupedScrollBackground() -> some View {
        scrollContentBackground(.hidden)
            .background(RemuxAppPalette.background.ignoresSafeArea())
    }

    @ViewBuilder
    func remuxSheetPresentationBackground() -> some View {
        if #available(iOS 26.0, *) {
            self
        } else {
            presentationBackground(.regularMaterial)
        }
    }

    func libraryHomeListRowSurface() -> some View {
        remuxAppListRowSurface()
    }

    func libraryHomeChrome(theme: TerminalTheme) -> some View {
        remuxAppChrome(theme: theme)
    }

    func libraryHomeGroupedScrollBackground() -> some View {
        remuxAppGroupedScrollBackground()
    }
}

private extension UIColor {
    static let remuxAppBackground = UIColor { traits in
        switch traits.userInterfaceStyle {
        case .dark:
            UIColor(white: 0.02, alpha: 1.0)
        default:
            .systemBackground
        }
    }

    static let remuxAppRowSurface = UIColor { traits in
        switch traits.userInterfaceStyle {
        case .dark:
            UIColor(white: 0.07, alpha: 1.0)
        default:
            UIColor(white: 0.96, alpha: 1.0)
        }
    }

    static let remuxAppSeparator = UIColor { traits in
        switch traits.userInterfaceStyle {
        case .dark:
            UIColor.white.withAlphaComponent(0.14)
        default:
            UIColor.black.withAlphaComponent(0.12)
        }
    }

    static let remuxAppSectionHeader = UIColor { traits in
        switch traits.userInterfaceStyle {
        case .dark:
            UIColor.white.withAlphaComponent(0.62)
        default:
            UIColor.black.withAlphaComponent(0.58)
        }
    }

    static let remuxAppToolbarTint = UIColor { traits in
        switch traits.userInterfaceStyle {
        case .dark:
            .white
        default:
            .black
        }
    }

    static let remuxAppControlAccent = UIColor { traits in
        switch traits.userInterfaceStyle {
        case .dark:
            .white
        default:
            .black
        }
    }

    static let remuxAppRowIconForeground = UIColor { traits in
        switch traits.userInterfaceStyle {
        case .dark:
            UIColor.white.withAlphaComponent(0.82)
        default:
            UIColor.black.withAlphaComponent(0.72)
        }
    }

    static let remuxAppRowIconSurface = UIColor { traits in
        switch traits.userInterfaceStyle {
        case .dark:
            UIColor.white.withAlphaComponent(0.08)
        default:
            UIColor.black.withAlphaComponent(0.06)
        }
    }
}
