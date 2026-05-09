import Foundation

enum SkillHealthSeverity: String, Hashable {
    case info
    case warning
    case critical
}

enum SkillsBarToolScreen: String, CaseIterable, Identifiable, Hashable {
    case commandPalette
    case health
    case smartCollections
    case conflicts
    case importExport
    case instructions
    case plugins
    case stats
    case settings
    case projects

    var id: String { rawValue }

    var title: String {
        switch self {
        case .commandPalette:
            return "Command Palette"
        case .health:
            return "Skill Health"
        case .smartCollections:
            return "Smart Collections"
        case .conflicts:
            return "Conflict Center"
        case .importExport:
            return "Import and Export"
        case .instructions:
            return "Instructions Hub"
        case .plugins:
            return "Plugin Updates"
        case .stats:
            return "Usage Stats"
        case .settings:
            return "Settings"
        case .projects:
            return "Project Skills"
        }
    }

    var iconName: String {
        switch self {
        case .commandPalette:
            return "command"
        case .health:
            return "heart.text.square"
        case .smartCollections:
            return "sparkles"
        case .conflicts:
            return "exclamationmark.triangle"
        case .importExport:
            return "arrow.up.arrow.down"
        case .instructions:
            return "doc.text"
        case .plugins:
            return "shippingbox"
        case .stats:
            return "chart.bar"
        case .settings:
            return "gearshape"
        case .projects:
            return "folder"
        }
    }
}

enum SkillHealthCategory: String, CaseIterable, Identifiable, Hashable {
    case invalidFrontmatter
    case missingDescription
    case duplicateTrigger
    case missingCollectionPath
    case unreadableFolder
    case stalePinnedItem

    var id: String { rawValue }

    var title: String {
        switch self {
        case .invalidFrontmatter:
            return "Invalid Frontmatter"
        case .missingDescription:
            return "Missing Descriptions"
        case .duplicateTrigger:
            return "Duplicate Triggers"
        case .missingCollectionPath:
            return "Missing Collection Paths"
        case .unreadableFolder:
            return "Unreadable Folders"
        case .stalePinnedItem:
            return "Stale Pins"
        }
    }
}

struct SkillHealthIssue: Identifiable, Hashable {
    let id: String
    let category: SkillHealthCategory
    let severity: SkillHealthSeverity
    let title: String
    let detail: String
    let path: String?
    let skillPath: String?
    let collectionID: UUID?
}

enum SkillConflictKind: String, Hashable {
    case trigger
    case name

    var title: String {
        switch self {
        case .trigger:
            return "Trigger"
        case .name:
            return "Name"
        }
    }
}

struct SkillConflictGroup: Identifiable, Hashable {
    let kind: SkillConflictKind
    let value: String
    let skills: [Skill]

    var id: String {
        "\(kind.rawValue)::\(value.lowercased())"
    }

    var title: String {
        "\(kind.title): \(value)"
    }
}

enum SmartCollectionKind: String, CaseIterable, Identifiable, Hashable {
    case recentlyModified
    case mostUsed
    case projectSkills
    case conflicts
    case unused
    case claudeOnly
    case codexPlugins

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recentlyModified:
            return "Recently Modified"
        case .mostUsed:
            return "Most Used"
        case .projectSkills:
            return "Project Skills"
        case .conflicts:
            return "Conflicts"
        case .unused:
            return "Unused"
        case .claudeOnly:
            return "Claude Only"
        case .codexPlugins:
            return "Codex Plugins"
        }
    }

    var detail: String {
        switch self {
        case .recentlyModified:
            return "Skills changed in the last 30 days."
        case .mostUsed:
            return "Skills with usage history, sorted by count."
        case .projectSkills:
            return "All skills from trusted project roots."
        case .conflicts:
            return "Skills involved in duplicate trigger or name conflicts."
        case .unused:
            return "Installed skills with no usage history yet."
        case .claudeOnly:
            return "Claude Code user, project, and plugin skills."
        case .codexPlugins:
            return "Skills installed through Codex plugins."
        }
    }

    var iconName: String {
        switch self {
        case .recentlyModified:
            return "clock.arrow.circlepath"
        case .mostUsed:
            return "chart.bar.fill"
        case .projectSkills:
            return "folder"
        case .conflicts:
            return "exclamationmark.triangle"
        case .unused:
            return "tray"
        case .claudeOnly:
            return "terminal"
        case .codexPlugins:
            return "shippingbox"
        }
    }
}

struct ResolvedSmartCollection: Identifiable, Hashable {
    let kind: SmartCollectionKind
    let skills: [Skill]

    var id: String { kind.id }
}

struct SkillValidationSummary: Hashable {
    let hasFrontmatter: Bool
    let hasName: Bool
    let hasDescription: Bool
    let recommendedMissingFields: [String]
    let exampleInvocation: String
    let previewTitle: String
    let previewDescription: String

    var statusTitle: String {
        if !hasFrontmatter {
            return "Invalid frontmatter"
        }
        if recommendedMissingFields.isEmpty {
            return "Ready"
        }
        return "Needs metadata"
    }
}

enum InstructionHubScope: String, Hashable {
    case global
    case project
}

struct InstructionHubItem: Identifiable, Hashable {
    let id: String
    let displayName: String
    let sourceLabel: String
    let scope: InstructionHubScope
    let projectName: String?
    let path: String
    let exists: Bool
    let lastModified: Date?
    let isReadable: Bool
    let isEmpty: Bool

    var healthTitle: String {
        if !exists {
            return "Missing"
        }
        if !isReadable {
            return "Unreadable"
        }
        if isEmpty {
            return "Empty"
        }
        return "Ready"
    }
}

struct PluginAwarenessItem: Identifiable, Hashable {
    let plugin: Plugin
    let skillCount: Int
    let changedRecently: Bool

    var id: String { plugin.id }
}

struct SkillLibraryAppPreferences: Codable, Hashable {
    var sortOptionRaw: String?
    var selectedTabRaw: String?
    var preferredAppearanceRaw: String?
    var showsWhatsNewSection: Bool?
    var preferredEditorRaw: String?
}

struct SkillLibraryExportSnapshot: Codable, Hashable {
    var schemaVersion: Int
    var exportedAt: Date
    var collections: [SkillCollection]
    var pinnedPaths: [String]
    var pinnedOrder: [String]
    var projectSkillRoots: [ProjectSkillRoot]
    var projectPinnedSkillPaths: [String: [String]]
    var appPreferences: SkillLibraryAppPreferences
}

struct SkillLibraryImportPreview: Hashable {
    let snapshot: SkillLibraryExportSnapshot

    var collectionCount: Int { snapshot.collections.count }
    var pinnedCount: Int { snapshot.pinnedPaths.count }
    var projectCount: Int { snapshot.projectSkillRoots.count }
    var projectPinnedCount: Int { snapshot.projectPinnedSkillPaths.values.reduce(0) { $0 + $1.count } }
}
