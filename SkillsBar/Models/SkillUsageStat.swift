import Foundation

struct SkillInvocation: Codable, Identifiable {
    var id: String { "\(sessionId)-\(timestamp.timeIntervalSince1970)-\(skillName)" }
    let skillName: String
    let args: String?
    let timestamp: Date
    let sessionId: String
    let projectPath: String?
}

struct SkillUsageStat: Identifiable {
    var id: String { skillName }
    let skillName: String
    let totalCount: Int
    let lastUsedDate: Date?
    let firstUsedDate: Date?
    let invocations: [SkillInvocation]

    var daysSinceLastUsed: Int? {
        guard let date = lastUsedDate else { return nil }
        return Calendar.current.dateComponents([.day], from: date, to: Date()).day
    }

    var isStale: Bool {
        guard let days = daysSinceLastUsed else { return false }
        return days >= 30
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
}

struct ParsedSessionFile: Codable {
    let path: String
    let lastModified: Date
    let fileSize: UInt64
    let invocations: [SkillInvocation]
}

struct UsageCache: Codable {
    var parsedFiles: [String: ParsedSessionFile] = [:]
    var lastFullScanDate: Date?
}
