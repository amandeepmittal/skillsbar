import AppKit
import SwiftUI

enum AppPreferenceKey {
    static let preferredAppearance = "preferredAppearance"
    static let showsWhatsNewSection = "showsWhatsNewSection"
    static let preferredEditor = "preferredEditor"
}

enum AppAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system:
            return "System"
        case .light:
            return "Light"
        case .dark:
            return "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system:
            return nil
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }
}

enum ExternalEditor: String, CaseIterable, Identifiable {
    case visualStudioCode
    case visualStudioCodeInsiders
    case webStorm
    case cursor
    case windsurf
    case zed
    case sublimeText
    case nova
    case bbEdit
    case textMate
    case fleet
    case intelliJIDEA
    case pyCharm
    case xcode

    var id: String { rawValue }

    var title: String {
        switch self {
        case .visualStudioCode:
            return "Visual Studio Code"
        case .visualStudioCodeInsiders:
            return "Visual Studio Code Insiders"
        case .webStorm:
            return "WebStorm"
        case .cursor:
            return "Cursor"
        case .windsurf:
            return "Windsurf"
        case .zed:
            return "Zed"
        case .sublimeText:
            return "Sublime Text"
        case .nova:
            return "Nova"
        case .bbEdit:
            return "BBEdit"
        case .textMate:
            return "TextMate"
        case .fleet:
            return "Fleet"
        case .intelliJIDEA:
            return "IntelliJ IDEA"
        case .pyCharm:
            return "PyCharm"
        case .xcode:
            return "Xcode"
        }
    }

    var shortTitle: String {
        switch self {
        case .visualStudioCode:
            return "VS Code"
        case .visualStudioCodeInsiders:
            return "VS Code Insiders"
        case .sublimeText:
            return "Sublime"
        case .intelliJIDEA:
            return "IntelliJ"
        default:
            return title
        }
    }

    var bundleIdentifiers: [String] {
        switch self {
        case .visualStudioCode:
            return ["com.microsoft.VSCode"]
        case .visualStudioCodeInsiders:
            return ["com.microsoft.VSCodeInsiders"]
        case .webStorm:
            return ["com.jetbrains.WebStorm"]
        case .cursor:
            return ["com.todesktop.230313mzl4w4u92"]
        case .windsurf:
            return ["com.exafunction.windsurf"]
        case .zed:
            return ["dev.zed.Zed"]
        case .sublimeText:
            return ["com.sublimetext.4", "com.sublimetext.3"]
        case .nova:
            return ["com.panic.Nova"]
        case .bbEdit:
            return ["com.barebones.bbedit"]
        case .textMate:
            return ["com.macromates.TextMate"]
        case .fleet:
            return ["com.jetbrains.fleet"]
        case .intelliJIDEA:
            return ["com.jetbrains.intellij"]
        case .pyCharm:
            return ["com.jetbrains.pycharm"]
        case .xcode:
            return ["com.apple.dt.Xcode"]
        }
    }

    var applicationURL: URL? {
        bundleIdentifiers.lazy.compactMap { bundleIdentifier in
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
        }.first
    }

    var isInstalled: Bool {
        applicationURL != nil
    }

    var openMenuTitle: String {
        "Open in \(shortTitle)"
    }

    static var installedEditors: [ExternalEditor] {
        allCases.filter(\.isInstalled)
    }

    static var defaultEditor: ExternalEditor {
        if visualStudioCode.isInstalled {
            return .visualStudioCode
        }

        return installedEditors.first ?? .visualStudioCode
    }

    static func resolved(for rawValue: String) -> ExternalEditor {
        guard let editor = ExternalEditor(rawValue: rawValue), editor.isInstalled else {
            return defaultEditor
        }

        return editor
    }
}
