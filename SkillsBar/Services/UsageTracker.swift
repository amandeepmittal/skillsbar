import Foundation

private let iso8601WithFractional: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
}()

private let iso8601Plain: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter
}()

@MainActor
final class UsageTracker: ObservableObject {
    @Published var stats: [String: SkillUsageStat] = [:]
    @Published var isLoading = false
    @Published var lastRefreshDate: Date?

    private var autoRefreshTimer: Timer?
    private static let autoRefreshInterval: TimeInterval = 12 * 60 * 60

    deinit {
        autoRefreshTimer?.invalidate()
    }

    private let cacheURL: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let directory = appSupport.appendingPathComponent("SkillsBar")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("usage-cache.json")
    }()

    // MARK: - Public API

    func stat(for skill: Skill) -> SkillUsageStat? {
        let source = Self.source(for: skill.source)
        let skillName = Self.normalizeTriggerCommand(skill.triggerCommand, source: source)
        return stats[Self.statsKey(for: skillName, source: source)]
    }

    var rankedStats: [SkillUsageStat] {
        Self.sortStats(Array(stats.values))
    }

    func rankedStats(for source: UsageSource) -> [SkillUsageStat] {
        Self.sortStats(stats.values.filter { $0.source == source })
    }

    var staleSkills: [SkillUsageStat] {
        rankedStats.filter { $0.isStale }
    }

    var mostUsed: SkillUsageStat? {
        rankedStats.first
    }

    var totalInvocations: Int {
        stats.values.reduce(0) { $0 + $1.totalCount }
    }

    func totalInvocations(for source: UsageSource) -> Int {
        stats.values
            .filter { $0.source == source }
            .reduce(0) { $0 + $1.totalCount }
    }

    func skillCount(for source: UsageSource) -> Int {
        stats.values.filter { $0.source == source }.count
    }

    var sourcesWithStats: [UsageSource] {
        UsageSource.allCases.filter { !rankedStats(for: $0).isEmpty }
    }

    static func identifier(for skill: Skill) -> String {
        let source = source(for: skill.source)
        let skillName = normalizeTriggerCommand(skill.triggerCommand, source: source)
        return statsKey(for: skillName, source: source)
    }

    // MARK: - Refresh

    func refresh() {
        guard !isLoading else { return }
        isLoading = true

        Task.detached(priority: .userInitiated) {
            let cache = await self.performIncrementalParse()
            let newStats = Self.buildStats(from: cache)
            await MainActor.run {
                self.stats = newStats
                self.isLoading = false
                self.lastRefreshDate = Date()
            }
            await self.saveCache(cache)
        }
    }

    func startAutoRefresh() {
        stopAutoRefresh()
        autoRefreshTimer = Timer.scheduledTimer(
            withTimeInterval: Self.autoRefreshInterval,
            repeats: true
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.refresh()
            }
        }
    }

    func stopAutoRefresh() {
        autoRefreshTimer?.invalidate()
        autoRefreshTimer = nil
    }

    // MARK: - Incremental Parse

    nonisolated private func performIncrementalParse() async -> UsageCache {
        var cache = await loadCache()
        let fileManager = FileManager.default
        let home = fileManager.homeDirectoryForCurrentUser.path

        for filePath in Self.claudeTranscriptPaths(home: home, fileManager: fileManager) {
            Self.refreshCachedFile(at: filePath, parser: Self.parseClaudeSessionFile, cache: &cache, fileManager: fileManager)
        }

        let codexHistoryPath = "\(home)/.codex/history.jsonl"
        if fileManager.fileExists(atPath: codexHistoryPath) {
            Self.refreshCachedFile(at: codexHistoryPath, parser: Self.parseCodexHistoryFile, cache: &cache, fileManager: fileManager)
        }

        cache.lastFullScanDate = Date()
        return cache
    }

    nonisolated private static func claudeTranscriptPaths(home: String, fileManager: FileManager) -> [String] {
        let projectsDirectory = "\(home)/.claude/projects"
        guard fileManager.fileExists(atPath: projectsDirectory) else { return [] }

        var paths: [String] = []
        if let projectDirectories = try? fileManager.contentsOfDirectory(atPath: projectsDirectory) {
            for projectDirectory in projectDirectories {
                let projectPath = "\(projectsDirectory)/\(projectDirectory)"
                var isDirectory: ObjCBool = false
                guard fileManager.fileExists(atPath: projectPath, isDirectory: &isDirectory), isDirectory.boolValue else {
                    continue
                }

                if let files = try? fileManager.contentsOfDirectory(atPath: projectPath) {
                    for file in files where file.hasSuffix(".jsonl") {
                        paths.append("\(projectPath)/\(file)")
                    }
                }
            }
        }

        return paths
    }

    nonisolated private static func refreshCachedFile(
        at path: String,
        parser: (String) -> [SkillInvocation],
        cache: inout UsageCache,
        fileManager: FileManager
    ) {
        guard let attributes = try? fileManager.attributesOfItem(atPath: path),
              let modifiedDate = attributes[.modificationDate] as? Date,
              let fileSize = attributes[.size] as? UInt64 else {
            return
        }

        if let cached = cache.parsedFiles[path],
           cached.lastModified == modifiedDate,
           cached.fileSize == fileSize {
            return
        }

        cache.parsedFiles[path] = ParsedSessionFile(
            path: path,
            lastModified: modifiedDate,
            fileSize: fileSize,
            invocations: parser(path)
        )
    }

    // MARK: - Parse Claude Session File

    nonisolated private static func parseClaudeSessionFile(at path: String) -> [SkillInvocation] {
        var invocations: [SkillInvocation] = []
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            if let date = iso8601WithFractional.date(from: string) { return date }
            if let date = iso8601Plain.date(from: string) { return date }
            return Date.distantPast
        }

        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return [] }
        let lines = data.split(separator: UInt8(ascii: "\n"))

        let components = path.components(separatedBy: "/")
        let projectPath: String? = {
            if let index = components.firstIndex(of: "projects"), index + 1 < components.count {
                return components[index + 1]
            }
            return nil
        }()

        let skillDirectoryPrefix = "Base directory for this skill:"

        for line in lines {
            guard let lineString = String(data: Data(line), encoding: .utf8) else { continue }

            if lineString.contains("\"Skill\""),
               let sessionLine = try? decoder.decode(SessionLine.self, from: Data(line)),
               sessionLine.type == "assistant",
               let content = sessionLine.message?.content {
                for block in content {
                    guard block.type == "tool_use",
                          block.name == "Skill",
                          let input = block.input,
                          let skillName = normalizedSkillName(input.skill, source: .claudeCode) else {
                        continue
                    }

                    invocations.append(SkillInvocation(
                        source: .claudeCode,
                        skillName: skillName,
                        args: input.args,
                        timestamp: sessionLine.timestamp ?? Date.distantPast,
                        sessionId: sessionLine.sessionId ?? "",
                        projectPath: projectPath
                    ))
                }
            }

            if lineString.contains(skillDirectoryPrefix),
               let sessionLine = try? decoder.decode(SessionLine.self, from: Data(line)),
               sessionLine.type == "user",
               let content = sessionLine.message?.content {
                for block in content {
                    guard block.type == "text",
                          let text = block.text,
                          let range = text.range(of: skillDirectoryPrefix) else {
                        continue
                    }

                    let pathString = text[range.upperBound...].trimmingCharacters(in: .whitespaces)
                    let skillPath = pathString.components(separatedBy: "\n").first ?? pathString
                    let folderName = URL(fileURLWithPath: skillPath).lastPathComponent
                    guard let skillName = normalizedSkillName(folderName, source: .claudeCode) else {
                        continue
                    }

                    invocations.append(SkillInvocation(
                        source: .claudeCode,
                        skillName: skillName,
                        args: nil,
                        timestamp: sessionLine.timestamp ?? Date.distantPast,
                        sessionId: sessionLine.sessionId ?? "",
                        projectPath: projectPath
                    ))
                }
            }
        }

        return invocations
    }

    // MARK: - Parse Codex History

    nonisolated private static func parseCodexHistoryFile(at path: String) -> [SkillInvocation] {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return [] }

        let decoder = JSONDecoder()
        var invocations: [SkillInvocation] = []

        for line in data.split(separator: UInt8(ascii: "\n")) {
            guard let entry = try? decoder.decode(CodexHistoryLine.self, from: Data(line)),
                  let text = entry.text else {
                continue
            }

            let timestamp = Date(timeIntervalSince1970: TimeInterval(entry.ts))
            for skillName in extractCodexSkillNames(from: text) {
                invocations.append(SkillInvocation(
                    source: .codexCLI,
                    skillName: skillName,
                    args: nil,
                    timestamp: timestamp,
                    sessionId: entry.sessionId,
                    projectPath: nil
                ))
            }
        }

        return invocations
    }

    nonisolated private static func extractCodexSkillNames(from text: String) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        var results: [String] = []

        if trimmed.hasPrefix("$") {
            let start = trimmed.index(after: trimmed.startIndex)
            let token = String(trimmed[start...].prefix(while: Self.isSkillNameCharacter))
            if token.contains(where: \.isLetter),
               let skillName = normalizedSkillName(token, source: .codexCLI) {
                results.append(skillName)
            }
        }

        let components = trimmed.split(whereSeparator: \.isWhitespace)
        if let first = components.first, first.lowercased() == "/skills" {
            if components.count >= 3, components[1].lowercased() == "open" {
                if let skillName = normalizedSkillName(String(components[2]), source: .codexCLI) {
                    results.append(skillName)
                }
            } else if components.count >= 2 {
                let candidate = components[1].lowercased()
                if candidate != "list" && candidate != "help",
                   let skillName = normalizedSkillName(String(components[1]), source: .codexCLI) {
                    results.append(skillName)
                }
            }
        }

        if let range = trimmed.range(of: "use /skills ", options: [.caseInsensitive]) {
            let remainder = trimmed[range.upperBound...]
            let token = String(remainder.prefix(while: Self.isSkillNameCharacter))
            if let skillName = normalizedSkillName(token, source: .codexCLI) {
                results.append(skillName)
            }
        }

        var seen: Set<String> = []
        return results.filter { seen.insert($0).inserted }
    }

    nonisolated private static func isSkillNameCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == "-" || character == "_" || character == "."
    }

    // MARK: - Build Stats

    nonisolated private static func buildStats(from cache: UsageCache) -> [String: SkillUsageStat] {
        var grouped: [String: [SkillInvocation]] = [:]

        for parsedFile in cache.parsedFiles.values {
            for invocation in parsedFile.invocations {
                let key = statsKey(for: invocation.skillName, source: invocation.source)
                grouped[key, default: []].append(invocation)
            }
        }

        var result: [String: SkillUsageStat] = [:]
        for (key, invocations) in grouped {
            let sortedInvocations = invocations.sorted { $0.timestamp < $1.timestamp }
            guard let firstInvocation = sortedInvocations.first else { continue }
            result[key] = SkillUsageStat(
                source: firstInvocation.source,
                skillName: firstInvocation.skillName,
                totalCount: sortedInvocations.count,
                lastUsedDate: sortedInvocations.last?.timestamp,
                firstUsedDate: sortedInvocations.first?.timestamp,
                invocations: sortedInvocations
            )
        }

        return result
    }

    nonisolated private static func sortStats(_ stats: [SkillUsageStat]) -> [SkillUsageStat] {
        stats.sorted { lhs, rhs in
            if lhs.totalCount != rhs.totalCount {
                return lhs.totalCount > rhs.totalCount
            }

            switch (lhs.lastUsedDate, rhs.lastUsedDate) {
            case let (leftDate?, rightDate?) where leftDate != rightDate:
                return leftDate > rightDate
            default:
                break
            }

            if lhs.source != rhs.source {
                return lhs.source.rawValue < rhs.source.rawValue
            }

            return lhs.skillName.localizedCaseInsensitiveCompare(rhs.skillName) == .orderedAscending
        }
    }

    // MARK: - Helpers

    nonisolated private static func normalizedSkillName(_ value: String?, source: UsageSource) -> String? {
        guard let value else { return nil }
        let normalized = normalizeTriggerCommand(value, source: source)
        return normalized.isEmpty ? nil : normalized
    }

    nonisolated static func normalizeTriggerCommand(_ triggerCommand: String, source: UsageSource) -> String {
        let trimmed = triggerCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        switch source {
        case .claudeCode:
            if trimmed.hasPrefix("/") {
                return String(trimmed.dropFirst())
            }
            return trimmed
        case .codexCLI:
            if trimmed.hasPrefix("$") {
                return String(trimmed.dropFirst())
            }
            return trimmed
        }
    }

    nonisolated static func statsKey(for skillName: String, source: UsageSource) -> String {
        "\(source.rawValue)::\(skillName)"
    }

    nonisolated static func source(for skillSource: SkillSource) -> UsageSource {
        switch skillSource {
        case .claudeCode:
            return .claudeCode
        case .codexCLI:
            return .codexCLI
        }
    }

    // MARK: - Cache I/O

    nonisolated private func loadCache() async -> UsageCache {
        let url = cacheURL
        guard let data = try? Data(contentsOf: url) else { return UsageCache() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            if let date = iso8601WithFractional.date(from: string) { return date }
            if let date = iso8601Plain.date(from: string) { return date }
            return Date.distantPast
        }
        return (try? decoder.decode(UsageCache.self, from: data)) ?? UsageCache()
    }

    nonisolated private func saveCache(_ cache: UsageCache) async {
        let url = cacheURL
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(iso8601WithFractional.string(from: date))
        }
        guard let data = try? encoder.encode(cache) else { return }
        try? data.write(to: url, options: .atomic)
    }
}

// MARK: - Claude Decode Structs

private struct SessionLine: Decodable {
    let type: String?
    let timestamp: Date?
    let sessionId: String?
    let message: SessionMessage?
}

private struct SessionMessage: Decodable {
    let content: [ContentBlock]?
}

private struct ContentBlock: Decodable {
    let type: String?
    let name: String?
    let text: String?
    let input: SkillInput?
}

private struct SkillInput: Decodable {
    let skill: String?
    let args: String?
}

// MARK: - Codex Decode Structs

private struct CodexHistoryLine: Decodable {
    let sessionId: String
    let ts: Int64
    let text: String?

    private enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case ts
        case text
    }
}
