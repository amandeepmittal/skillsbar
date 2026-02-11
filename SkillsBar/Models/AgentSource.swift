import Foundation

enum AgentSource: Hashable {
    case user
    case plugin

    var sectionTitle: String {
        switch self {
        case .user: return "User Agents"
        case .plugin: return "Plugin Agents"
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
}
