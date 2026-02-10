import Foundation

enum SkillSource: Hashable {
    case claudeCode(ClaudeCodeSection)
    case codexCLI(CodexSection)

    enum ClaudeCodeSection: String, Hashable {
        case user = "User Skills"
        case plugin = "Plugin Skills"
    }

    enum CodexSection: String, Hashable {
        case builtin = "Built-in Skills"
        case user = "User Skills"
    }

    var groupTitle: String {
        switch self {
        case .claudeCode: return "Claude Code"
        case .codexCLI: return "Codex CLI"
        }
    }

    var sectionTitle: String {
        switch self {
        case .claudeCode(let section): return section.rawValue
        case .codexCLI(let section): return section.rawValue
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
        case .codexCLI(.builtin): return "purple"
        case .codexCLI(.user): return "purple"
        }
    }
}
