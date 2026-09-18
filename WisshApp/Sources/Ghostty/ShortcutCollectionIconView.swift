import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct ShortcutPaletteTabIcon: View {
    let tab: ShortcutPaletteTabID
    let snapshot: ShortcutStoreSnapshot

    var body: some View {
        switch tab {
        case .favorites:
            Image(systemName: "star")
                .font(.system(size: 16, weight: .semibold))
                .symbolRenderingMode(.monochrome)
        case .collection(let collection):
            ShortcutCollectionIconView(
                icon: snapshot.collection(id: collection)?.icon ?? .folder,
                variant: .tab
            )
        case .appAction(let action):
            Image(systemName: action.systemImageName)
                .font(.system(size: 16, weight: .semibold))
                .symbolRenderingMode(.monochrome)
        }
    }
}

struct ShortcutCollectionIconView: View {
    enum Variant {
        case tab
        case settings
    }

    let icon: ShortcutCollectionIcon
    var variant: Variant = .settings

    var body: some View {
        switch icon.rawValue {
        case ShortcutCollectionIcon.claude.rawValue:
            Image("ShortcutClaudeMark")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(
                    width: variant == .tab ? 18.5 : 19.5,
                    height: variant == .tab ? 18.5 : 19.5
                )
        case ShortcutCollectionIcon.codex.rawValue:
            Image("ShortcutOpenAIMark")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(
                    width: variant == .tab ? 18.5 : 19.5,
                    height: variant == .tab ? 18.5 : 19.5
                )
        default:
            Image(systemName: resolvedSystemImageName)
                .font(.system(size: variant == .tab ? 16 : 15.5, weight: .semibold))
                .symbolRenderingMode(.monochrome)
        }
    }

    private var resolvedSystemImageName: String {
        #if canImport(UIKit)
        UIImage(systemName: icon.systemImageName) == nil ? "questionmark.circle" : icon.systemImageName
        #else
        icon.systemImageName
        #endif
    }
}
