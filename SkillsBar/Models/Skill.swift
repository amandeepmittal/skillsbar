import Foundation

struct Skill: Identifiable, Hashable {
    let id: String
    let name: String
    let description: String
    let source: SkillSource
    let path: String
    var version: String?
    var body: String = ""
    var lastModified: Date?
    var folderContents: [String] = []
    var folderDirectories: Set<String> = []
    var directoryContents: [String: [String]] = [:]

    init(name: String, description: String, source: SkillSource, path: String, version: String? = nil, body: String = "", lastModified: Date? = nil, folderContents: [String] = [], folderDirectories: Set<String> = [], directoryContents: [String: [String]] = [:]) {
        self.id = path
        self.name = name
        self.description = description
        self.source = source
        self.path = path
        self.version = version
        self.body = body
        self.lastModified = lastModified
        self.folderContents = folderContents
        self.folderDirectories = folderDirectories
        self.directoryContents = directoryContents
    }

    var displayName: String {
        name.isEmpty ? URL(fileURLWithPath: path).deletingLastPathComponent().lastPathComponent : name
    }

    var shortDescription: String {
        let firstLine = description.components(separatedBy: .newlines).first ?? description
        if firstLine.count > 120 {
            return String(firstLine.prefix(117)) + "..."
        }
        return firstLine
    }

    var isNew: Bool {
        guard let date = lastModified else { return false }
        return Date().timeIntervalSince(date) < 86400
    }

    var formattedLastModified: String? {
        guard let date = lastModified else { return nil }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    var triggerCommand: String {
        switch source {
        case .claudeCode(.user):
            // ~/.claude/skills/<folder-name>/SKILL.md -> /folder-name
            let folderName = URL(fileURLWithPath: path).deletingLastPathComponent().lastPathComponent
            return "/\(folderName)"

        case .claudeCode(.plugin):
            // ~/.claude/plugins/cache/<repo>/<plugin>/<ver>/skills/<skill>/SKILL.md
            // trigger: plugin-name:skill-name
            let components = path.components(separatedBy: "/")
            if let skillsIdx = components.lastIndex(of: "skills"),
               skillsIdx > 1,
               skillsIdx + 1 < components.count {
                let pluginName = components[skillsIdx - 2]
                let skillName = components[skillsIdx + 1]
                return "\(pluginName):\(skillName)"
            }
            let folderName = URL(fileURLWithPath: path).deletingLastPathComponent().lastPathComponent
            return folderName

        case .codexCLI(.builtin):
            let folderName = URL(fileURLWithPath: path).deletingLastPathComponent().lastPathComponent
            return folderName

        case .codexCLI(.user):
            let folderName = URL(fileURLWithPath: path).deletingLastPathComponent().lastPathComponent
            return folderName
        }
    }

    var triggerHint: String {
        switch source {
        case .claudeCode(.user):
            return "Type in Claude Code CLI"
        case .claudeCode(.plugin):
            return "Use the Skill tool or type /skill-name in Claude Code"
        case .codexCLI(.builtin):
            return "Available by default in Codex CLI"
        case .codexCLI(.user):
            return "Available as an installed skill in Codex CLI"
        }
    }
}
