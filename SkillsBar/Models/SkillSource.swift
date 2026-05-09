import Foundation

struct ProjectSkillRoot: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var path: String
    var isEnabled: Bool
    let createdAt: Date
    var updatedAt: Date

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case path
        case isEnabled
        case createdAt
        case updatedAt
    }

    init(
        id: UUID = UUID(),
        name: String? = nil,
        path: String,
        isEnabled: Bool = true,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        let standardizedPath = (path as NSString).standardizingPath
        let trimmedName = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.id = id
        self.path = standardizedPath
        if let trimmedName, !trimmedName.isEmpty {
            self.name = trimmedName
        } else {
            self.name = URL(fileURLWithPath: standardizedPath).lastPathComponent
        }
        self.isEnabled = isEnabled
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Project"
        path = (try container.decode(String.self, forKey: .path) as NSString).standardizingPath
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
    }

    var claudeSkillsPath: String {
        (path as NSString).appendingPathComponent(".claude/skills")
    }
}

enum ProjectSkillRootStatus: Equatable {
    case disabled
    case available
    case missingSkillsFolder
    case missingProjectFolder

    var title: String {
        switch self {
        case .disabled:
            return "Disabled"
        case .available:
            return "Ready"
        case .missingSkillsFolder:
            return "No .claude/skills"
        case .missingProjectFolder:
            return "Missing"
        }
    }

    var isUnavailable: Bool {
        switch self {
        case .missingSkillsFolder, .missingProjectFolder:
            return true
        case .disabled, .available:
            return false
        }
    }
}

enum SkillSourceCategory: String, CaseIterable, Hashable {
    case user
    case plugin
    case project
    case builtin
}

struct SkillConflictSummary: Hashable {
    let triggerMatchCount: Int
    let nameMatchCount: Int
    let matchingSkillDescriptions: [String]

    var totalCount: Int {
        matchingSkillDescriptions.count
    }

    var label: String {
        totalCount == 1 ? "Conflict" : "\(totalCount) conflicts"
    }

    var helpText: String {
        var lines: [String] = []

        if triggerMatchCount > 0 {
            lines.append("\(triggerMatchCount) matching trigger")
        }
        if nameMatchCount > 0 {
            lines.append("\(nameMatchCount) matching name")
        }

        lines.append(contentsOf: matchingSkillDescriptions.prefix(8))

        if matchingSkillDescriptions.count > 8 {
            lines.append("and \(matchingSkillDescriptions.count - 8) more")
        }

        return lines.joined(separator: "\n")
    }
}

enum SkillSource: Hashable {
    case claudeCode(ClaudeCodeSection)
    case codexCLI(CodexSection)

    enum ClaudeCodeSection: Hashable {
        case user
        case plugin
        case project(ProjectSkillRoot)

        var title: String {
            switch self {
            case .user:
                return "User Skills"
            case .plugin:
                return "Plugin Skills"
            case .project:
                return "Project Skill"
            }
        }
    }

    enum CodexSection: String, Hashable {
        case builtin = "Built-in Skills"
        case plugin = "Plugin Skills"
        case user = "User Skills"
    }

    var groupTitle: String {
        switch self {
        case .claudeCode: return "Claude Code"
        case .codexCLI: return "Codex"
        }
    }

    var sectionTitle: String {
        switch self {
        case .claudeCode(let section): return section.title
        case .codexCLI(let section): return section.rawValue
        }
    }

    var projectName: String? {
        switch self {
        case .claudeCode(.project(let root)):
            return root.name
        case .claudeCode, .codexCLI:
            return nil
        }
    }

    var projectRootPath: String? {
        switch self {
        case .claudeCode(.project(let root)):
            return root.path
        case .claudeCode, .codexCLI:
            return nil
        }
    }

    var isProjectSkill: Bool {
        projectRootPath != nil
    }

    var searchCategory: SkillSourceCategory {
        switch self {
        case .claudeCode(.user), .codexCLI(.user):
            return .user
        case .claudeCode(.plugin), .codexCLI(.plugin):
            return .plugin
        case .claudeCode(.project):
            return .project
        case .codexCLI(.builtin):
            return .builtin
        }
    }

    var shortScopeLabel: String {
        switch self {
        case .claudeCode(.user):
            return "Claude user"
        case .claudeCode(.plugin):
            return "Claude plugin"
        case .claudeCode(.project(let root)):
            return "\(root.name) project"
        case .codexCLI(.builtin):
            return "Codex built-in"
        case .codexCLI(.plugin):
            return "Codex plugin"
        case .codexCLI(.user):
            return "Codex user"
        }
    }

    var iconName: String {
        switch self {
        case .claudeCode: return "ClaudeLogo"
        case .codexCLI: return "OpenAILogo"
        }
    }

    var isCustomIcon: Bool { true }

    var badgeColor: String {
        switch self {
        case .claudeCode(.user): return "orange"
        case .claudeCode(.plugin): return "orange"
        case .claudeCode(.project(_)): return "blue"
        case .codexCLI(.builtin): return "purple"
        case .codexCLI(.plugin): return "purple"
        case .codexCLI(.user): return "purple"
        }
    }
}
