import Foundation

enum UsageSource: String, Codable, CaseIterable, Hashable {
    case claudeCode
    case codexCLI

    var displayName: String {
        switch self {
        case .claudeCode:
            return "Claude Code"
        case .codexCLI:
            return "Codex"
        }
    }

    var commandPrefix: String {
        switch self {
        case .claudeCode:
            return "/"
        case .codexCLI:
            return "$"
        }
    }

    var shortLabel: String {
        switch self {
        case .claudeCode:
            return "Claude"
        case .codexCLI:
            return "Codex"
        }
    }
}

struct SkillInvocation: Codable, Identifiable {
    let source: UsageSource
    let skillName: String
    let args: String?
    let timestamp: Date
    let sessionId: String
    let projectPath: String?

    var id: String {
        "\(source.rawValue)-\(sessionId)-\(timestamp.timeIntervalSince1970)-\(skillName)"
    }

    init(source: UsageSource, skillName: String, args: String?, timestamp: Date, sessionId: String, projectPath: String?) {
        self.source = source
        self.skillName = skillName
        self.args = args
        self.timestamp = timestamp
        self.sessionId = sessionId
        self.projectPath = projectPath
    }

    private enum CodingKeys: String, CodingKey {
        case source
        case skillName
        case args
        case timestamp
        case sessionId
        case projectPath
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        source = try container.decodeIfPresent(UsageSource.self, forKey: .source) ?? .claudeCode
        skillName = try container.decode(String.self, forKey: .skillName)
        args = try container.decodeIfPresent(String.self, forKey: .args)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        sessionId = try container.decode(String.self, forKey: .sessionId)
        projectPath = try container.decodeIfPresent(String.self, forKey: .projectPath)
    }
}

struct SkillUsageStat: Identifiable {
    let source: UsageSource
    let skillName: String
    let totalCount: Int
    let lastUsedDate: Date?
    let firstUsedDate: Date?
    let invocations: [SkillInvocation]

    var id: String {
        "\(source.rawValue)::\(skillName)"
    }

    var displayCommand: String {
        source.commandPrefix + skillName
    }

    var frequencyDescription: String {
        guard let first = firstUsedDate, let last = lastUsedDate else {
            return "No usage data"
        }
        let daySpan = max(1, Calendar.current.dateComponents([.day], from: first, to: last).day ?? 1)
        if daySpan < 7 {
            return "\(totalCount) uses"
        }
        let perWeek = Double(totalCount) / (Double(daySpan) / 7.0)
        if perWeek >= 1 {
            return "~\(Int(perWeek.rounded()))x/week"
        }
        let perMonth = Double(totalCount) / (Double(daySpan) / 30.0)
        return "~\(Int(perMonth.rounded()))x/month"
    }

    func scoped(since cutoffDate: Date?) -> SkillUsageStat? {
        let scopedInvocations: [SkillInvocation]
        if let cutoffDate {
            scopedInvocations = invocations.filter { $0.timestamp >= cutoffDate }
        } else {
            scopedInvocations = invocations
        }

        let sortedInvocations = scopedInvocations.sorted { $0.timestamp < $1.timestamp }
        guard let firstInvocation = sortedInvocations.first else { return nil }

        return SkillUsageStat(
            source: firstInvocation.source,
            skillName: firstInvocation.skillName,
            totalCount: sortedInvocations.count,
            lastUsedDate: sortedInvocations.last?.timestamp,
            firstUsedDate: sortedInvocations.first?.timestamp,
            invocations: sortedInvocations
        )
    }
}

struct ParsedSessionFile: Codable {
    let path: String
    let lastModified: Date
    let fileSize: UInt64
    let invocations: [SkillInvocation]
}

struct UsageCache: Codable {
    var schemaVersion: Int = 1
    var parsedFiles: [String: ParsedSessionFile] = [:]
    var lastFullScanDate: Date?
}

struct UsageHistoryStore: Codable {
    var schemaVersion: Int = 1
    var events: [String: SkillInvocation] = [:]
    var lastUpdatedDate: Date?
}
