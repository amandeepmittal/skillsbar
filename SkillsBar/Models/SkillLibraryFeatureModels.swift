import Foundation

enum SkillHealthSeverity: String, Hashable {
    case info
    case warning
    case critical
}

enum SkillsBarToolScreen: String, CaseIterable, Identifiable, Hashable {
    case commandPalette
    case health
    case instructions
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
        case .instructions:
            return "Instructions Hub"
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
        case .instructions:
            return "doc.text"
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
