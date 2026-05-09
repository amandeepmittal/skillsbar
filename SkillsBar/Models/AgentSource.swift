import Foundation

enum AgentSource: Hashable {
    case user
    case plugin
    case project(ProjectSkillRoot)

    var sectionTitle: String {
        switch self {
        case .user: return "User Agents"
        case .plugin: return "Plugin Agents"
        case .project(let root): return "\(root.name) Project Agents"
        }
    }

    var groupTitle: String {
        "Agents"
    }

    var iconName: String {
        "ClaudeLogo"
    }

    var badgeColor: String {
        "cyan"
    }

    var projectName: String? {
        switch self {
        case .project(let root):
            return root.name
        case .user, .plugin:
            return nil
        }
    }

    var projectRootPath: String? {
        switch self {
        case .project(let root):
            return root.path
        case .user, .plugin:
            return nil
        }
    }

    var isProjectAgent: Bool {
        projectRootPath != nil
    }
}
