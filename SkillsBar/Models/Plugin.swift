import Foundation

struct Plugin: Identifiable, Hashable {
    enum Source: Hashable {
        case codexCLI

        var groupTitle: String { "Codex CLI" }
        var sectionTitle: String { "Installed Plugins" }
        var iconName: String { "OpenAILogo" }
    }

    let id: String
    let name: String
    let displayNameOverride: String?
    let shortDescriptionOverride: String?
    let description: String
    let version: String?
    let source: Source
    let path: String
    let manifestPath: String
    let publisher: String?
    let authorName: String?
    let homepage: String?
    let repository: String?
    let keywords: [String]
    let capabilities: [String]
    let defaultPrompt: String?
    let lastModified: Date?

    init(
        name: String,
        displayNameOverride: String? = nil,
        shortDescriptionOverride: String? = nil,
        description: String,
        version: String? = nil,
        source: Source = .codexCLI,
        path: String,
        manifestPath: String,
        publisher: String? = nil,
        authorName: String? = nil,
        homepage: String? = nil,
        repository: String? = nil,
        keywords: [String] = [],
        capabilities: [String] = [],
        defaultPrompt: String? = nil,
        lastModified: Date? = nil
    ) {
        self.id = path
        self.name = name
        self.displayNameOverride = displayNameOverride
        self.shortDescriptionOverride = shortDescriptionOverride
        self.description = description
        self.version = version
        self.source = source
        self.path = path
        self.manifestPath = manifestPath
        self.publisher = publisher
        self.authorName = authorName
        self.homepage = homepage
        self.repository = repository
        self.keywords = keywords
        self.capabilities = capabilities
        self.defaultPrompt = defaultPrompt
        self.lastModified = lastModified
    }

    var displayName: String {
        let candidate = displayNameOverride?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !candidate.isEmpty {
            return candidate
        }

        let fallback = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !fallback.isEmpty {
            return fallback
        }

        return URL(fileURLWithPath: path).lastPathComponent
    }

    var shortDescription: String {
        let candidate = shortDescriptionOverride?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !candidate.isEmpty {
            return candidate
        }

        let firstLine = description
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .newlines)
            .first ?? ""
        if firstLine.count > 120 {
            return String(firstLine.prefix(117)) + "..."
        }
        return firstLine
    }

    var formattedLastModified: String? {
        guard let date = lastModified else { return nil }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
