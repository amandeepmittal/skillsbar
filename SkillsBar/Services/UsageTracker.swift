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

private let usageCacheSchemaVersion = 7
private let maxJSONLineBytes = 16 * 1024 * 1024

private let codexRolloutSkillSignalBytes = [
    Array("$".utf8),
    Array("/skills".utf8),
    Array("Using".utf8),
    Array("using".utf8),
    Array("Invoking".utf8),
    Array("invoking".utf8),
]

@MainActor
final class UsageTracker: ObservableObject {
    @Published var stats: [String: SkillUsageStat] = [:]
    @Published var isLoading = false
    @Published var lastRefreshDate: Date?

    private var autoRefreshTimer: Timer?
    private var watcher: FSEventsWatcher?
    private var watchedRefreshTask: Task<Void, Never>?
    private var lastWatchedRefreshDate: Date?
    private static let autoRefreshInterval: TimeInterval = 12 * 60 * 60
    private static let watchedRefreshDelay: UInt64 = 5 * 1_000_000_000
    private static let watchedRefreshCooldown: TimeInterval = 30

    deinit {
        autoRefreshTimer?.invalidate()
        watchedRefreshTask?.cancel()
        watcher?.stop()
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
            let cachedSnapshot = await self.loadCache()
            let cachedStats = Self.buildStats(from: cachedSnapshot)
            if !cachedStats.isEmpty {
                await MainActor.run {
                    self.stats = cachedStats
                    self.lastRefreshDate = cachedSnapshot.lastFullScanDate
                }
            }

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
        startWatching()
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
        watchedRefreshTask?.cancel()
        watchedRefreshTask = nil
        watcher?.stop()
        watcher = nil
    }

    private func startWatching() {
        watcher?.stop()

        let fileManager = FileManager.default
        let home = fileManager.homeDirectoryForCurrentUser.path
        let watchPaths = [
            "\(home)/.claude/projects",
            "\(home)/.codex/history.jsonl",
            "\(home)/.codex/sessions",
        ].filter { fileManager.fileExists(atPath: $0) }

        watcher = FSEventsWatcher(paths: watchPaths) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.scheduleWatchedRefresh()
            }
        }
        watcher?.start()
    }

    private func scheduleWatchedRefresh() {
        watchedRefreshTask?.cancel()
        watchedRefreshTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.watchedRefreshDelay)
            guard !Task.isCancelled else { return }
            if let lastWatchedRefreshDate = self?.lastWatchedRefreshDate,
               Date().timeIntervalSince(lastWatchedRefreshDate) < Self.watchedRefreshCooldown {
                return
            }
            self?.lastWatchedRefreshDate = Date()
            self?.refresh()
        }
    }

    // MARK: - Incremental Parse

    nonisolated private func performIncrementalParse() async -> UsageCache {
        var cache = await loadCache()
        cache.schemaVersion = usageCacheSchemaVersion
        let fileManager = FileManager.default
        let home = fileManager.homeDirectoryForCurrentUser.path

        for filePath in Self.claudeTranscriptPaths(home: home, fileManager: fileManager) {
            Self.refreshCachedFile(at: filePath, parser: Self.parseClaudeSessionFile, cache: &cache, fileManager: fileManager)
        }

        let codexHistoryPath = "\(home)/.codex/history.jsonl"
        if fileManager.fileExists(atPath: codexHistoryPath) {
            Self.refreshCachedFile(at: codexHistoryPath, parser: Self.parseCodexHistoryFile, cache: &cache, fileManager: fileManager)
        }

        for filePath in Self.codexDesktopSessionPaths(home: home, fileManager: fileManager) {
            Self.refreshCachedFile(at: filePath, parser: Self.parseCodexDesktopSessionFile, cache: &cache, fileManager: fileManager)
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

    nonisolated private static func codexDesktopSessionPaths(home: String, fileManager: FileManager) -> [String] {
        let sessionsDirectory = "\(home)/.codex/sessions"
        return jsonlFilePathsRecursively(in: sessionsDirectory, fileManager: fileManager)
    }

    nonisolated private static func jsonlFilePathsRecursively(in directory: String, fileManager: FileManager) -> [String] {
        guard fileManager.fileExists(atPath: directory),
              let enumerator = fileManager.enumerator(atPath: directory) else {
            return []
        }

        var paths: [String] = []
        while let relativePath = enumerator.nextObject() as? String {
            guard relativePath.hasSuffix(".jsonl") else { continue }
            paths.append((directory as NSString).appendingPathComponent(relativePath))
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
           Self.cacheDate(cached.lastModified, matches: modifiedDate),
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

        let components = path.components(separatedBy: "/")
        let projectPath: String? = {
            if let index = components.firstIndex(of: "projects"), index + 1 < components.count {
                return components[index + 1]
            }
            return nil
        }()

        let skillDirectoryPrefix = "Base directory for this skill:"

        readJSONLines(at: path) { line in
            guard let lineString = String(data: line, encoding: .utf8) else { return }

            if lineString.contains("\"Skill\""),
               let sessionLine = try? decoder.decode(SessionLine.self, from: line),
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
               let sessionLine = try? decoder.decode(SessionLine.self, from: line),
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
        let decoder = JSONDecoder()
        var invocations: [SkillInvocation] = []

        readJSONLines(at: path) { line in
            guard let entry = try? decoder.decode(CodexHistoryLine.self, from: line),
                  let text = entry.text else {
                return
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

    nonisolated private static func parseCodexDesktopSessionFile(at path: String) -> [SkillInvocation] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            if let date = iso8601WithFractional.date(from: string) { return date }
            if let date = iso8601Plain.date(from: string) { return date }
            return Date.distantPast
        }

        var sessionId = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
        var projectPath: String?
        var isCodexDesktopSession = false
        var candidates: [CodexSkillCandidate] = []

        readJSONLines(at: path) { line in
            if containsByteSequence(line, Array(#""type":"session_meta""#.utf8)),
               let entry = try? decoder.decode(CodexRolloutLine.self, from: line),
               let payload = entry.payload {
                sessionId = payload.id ?? sessionId
                projectPath = payload.cwd
                isCodexDesktopSession = payload.originator == "Codex Desktop"
                return
            }

            guard isCodexDesktopSession,
                  codexRolloutLineContainsSkillSignal(line),
                  let entry = try? decoder.decode(CodexRolloutLine.self, from: line) else {
                return
            }

            guard isCodexDesktopSession,
                  entry.type == "response_item",
                  entry.payload?.type == "message",
                  let role = entry.payload?.role,
                  let content = entry.payload?.content else {
                return
            }

            let text = content.compactMap(\.text).joined(separator: "\n")
            let timestamp = entry.timestamp ?? Date.distantPast

            switch role {
            case "user":
                for skillName in extractCodexSkillNames(from: text) {
                    candidates.append(CodexSkillCandidate(skillName: skillName, timestamp: timestamp, isExplicitTrigger: true))
                }
            case "assistant":
                for skillName in extractCodexAssistantSkillNames(from: text) {
                    candidates.append(CodexSkillCandidate(skillName: skillName, timestamp: timestamp, isExplicitTrigger: false))
                }
            default:
                return
            }
        }

        var invocations: [SkillInvocation] = []
        var lastExplicitTriggerBySkill: [String: Date] = [:]
        var seenInvocationKeys: Set<String> = []
        let duplicateWindow: TimeInterval = 15 * 60

        for candidate in candidates {
            if candidate.isExplicitTrigger {
                lastExplicitTriggerBySkill[candidate.skillName] = candidate.timestamp
            } else if let explicitDate = lastExplicitTriggerBySkill[candidate.skillName],
                      abs(candidate.timestamp.timeIntervalSince(explicitDate)) <= duplicateWindow {
                continue
            }

            let timestampKey = Int(candidate.timestamp.timeIntervalSince1970)
            let invocationKey = "\(sessionId)::\(timestampKey)::\(candidate.skillName)"
            guard seenInvocationKeys.insert(invocationKey).inserted else { continue }

            invocations.append(SkillInvocation(
                source: .codexCLI,
                skillName: candidate.skillName,
                args: nil,
                timestamp: candidate.timestamp,
                sessionId: sessionId,
                projectPath: projectPath
            ))
        }

        return invocations
    }

    nonisolated private static func extractCodexSkillNames(from text: String) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        var results: [String] = []

        if let regex = try? NSRegularExpression(pattern: #"(^|[^A-Za-z0-9_])\$([A-Za-z0-9][A-Za-z0-9._:-]*)"#) {
            let nsText = trimmed as NSString
            let fullRange = NSRange(location: 0, length: nsText.length)
            for match in regex.matches(in: trimmed, range: fullRange) {
                guard match.numberOfRanges > 2 else { continue }
                let token = nsText.substring(with: match.range(at: 2))
                guard token.contains(where: \.isLetter),
                      let skillName = normalizedSkillName(token, source: .codexCLI) else {
                    continue
                }
                results.append(skillName)
            }
        }

        if let regex = try? NSRegularExpression(pattern: #"<skill>\s*<name>\s*([A-Za-z0-9][A-Za-z0-9._:-]*)\s*</name>"#) {
            let nsText = trimmed as NSString
            let fullRange = NSRange(location: 0, length: nsText.length)
            for match in regex.matches(in: trimmed, range: fullRange) {
                guard match.numberOfRanges > 1 else { continue }
                let token = nsText.substring(with: match.range(at: 1))
                if let skillName = normalizedSkillName(token, source: .codexCLI) {
                    results.append(skillName)
                }
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

    nonisolated private static func readJSONLines(at path: String, handleLine: (Data) -> Void) {
        guard let fileHandle = try? FileHandle(forReadingFrom: URL(fileURLWithPath: path)) else { return }
        defer { try? fileHandle.close() }

        let delimiter = UInt8(ascii: "\n")
        let delimiterData = Data([delimiter])
        let chunkSize = 1024 * 1024
        var buffer = Data()
        var isSkippingOversizedLine = false

        while true {
            guard let chunk = try? fileHandle.read(upToCount: chunkSize),
                  !chunk.isEmpty else {
                break
            }

            var chunkStart = chunk.startIndex
            if isSkippingOversizedLine {
                if let newlineIndex = chunk[chunkStart...].firstIndex(of: delimiter) {
                    isSkippingOversizedLine = false
                    chunkStart = chunk.index(after: newlineIndex)
                } else {
                    continue
                }
            }

            if chunkStart != chunk.endIndex {
                buffer.append(chunk[chunkStart...])
            }

            while let range = buffer.firstRange(of: delimiterData) {
                let line = buffer.subdata(in: buffer.startIndex..<range.lowerBound)
                if !line.isEmpty && line.count <= maxJSONLineBytes {
                    handleLine(line)
                }
                buffer.removeSubrange(buffer.startIndex..<range.upperBound)
            }

            if buffer.count > maxJSONLineBytes {
                buffer.removeAll(keepingCapacity: true)
                isSkippingOversizedLine = true
            }
        }

        if !isSkippingOversizedLine && !buffer.isEmpty && buffer.count <= maxJSONLineBytes {
            handleLine(buffer)
        }
    }

    nonisolated private static func codexRolloutLineContainsSkillSignal<C: Collection>(_ line: C) -> Bool where C.Element == UInt8 {
        codexRolloutSkillSignalBytes.contains { containsByteSequence(line, $0) }
    }

    nonisolated private static func containsByteSequence<C: Collection>(_ haystack: C, _ needle: [UInt8]) -> Bool where C.Element == UInt8 {
        guard !needle.isEmpty else { return true }

        var index = haystack.startIndex
        while index != haystack.endIndex {
            var currentIndex = index
            var needleIndex = needle.startIndex

            while needleIndex != needle.endIndex,
                  currentIndex != haystack.endIndex,
                  haystack[currentIndex] == needle[needleIndex] {
                haystack.formIndex(after: &currentIndex)
                needle.formIndex(after: &needleIndex)
            }

            if needleIndex == needle.endIndex {
                return true
            }

            haystack.formIndex(after: &index)
        }

        return false
    }

    nonisolated private static func extractCodexAssistantSkillNames(from text: String) -> [String] {
        let patterns = [
            #"(?i)\busing\s+(?:the\s+)?skill:?\s+`?([A-Za-z0-9][A-Za-z0-9._:-]*)`?"#,
            #"(?i)\busing\s+(?:the\s+)?`?([A-Za-z0-9][A-Za-z0-9._:-]*)`?\s+(?:skill|guidance)\b"#,
            #"(?i)\binvoking\s+(?:the\s+)?skill:?\s+`?([A-Za-z0-9][A-Za-z0-9._:-]*)`?"#,
        ]

        var results: [String] = []
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            for match in regex.matches(in: text, range: fullRange) {
                guard match.numberOfRanges > 1 else { continue }
                let token = nsText.substring(with: match.range(at: 1))
                if let skillName = normalizedSkillName(token, source: .codexCLI) {
                    results.append(skillName)
                }
            }
        }

        var seen: Set<String> = []
        return results.filter { seen.insert($0).inserted }
    }

    nonisolated private static func isSkillNameCharacter(_ character: Character) -> Bool {
        // Codex plugin skills use identifiers like "plugin-name:skill-name".
        character.isLetter || character.isNumber || character == "-" || character == "_" || character == "." || character == ":"
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
        guard !normalized.isEmpty else { return nil }

        if source == .codexCLI, !isLikelyCodexSkillIdentifier(normalized) {
            return nil
        }

        return normalized
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

    nonisolated private static func isLikelyCodexSkillIdentifier(_ value: String) -> Bool {
        value == value.lowercased()
            && value.contains(where: \.isLetter)
            && value.allSatisfy(isSkillNameCharacter)
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
        guard var cache = try? decoder.decode(UsageCache.self, from: data) else {
            return UsageCache(schemaVersion: usageCacheSchemaVersion)
        }

        if cache.schemaVersion != usageCacheSchemaVersion {
            cache.schemaVersion = usageCacheSchemaVersion
            cache.parsedFiles = cache.parsedFiles.filter { !Self.shouldReparseForUsageSchemaUpgrade($0.key) }
        }

        return cache
    }

    nonisolated private static func shouldReparseForUsageSchemaUpgrade(_ path: String) -> Bool {
        path.contains("/.codex/sessions/") || path.hasSuffix("/.codex/history.jsonl")
    }

    nonisolated private static func cacheDate(_ cachedDate: Date, matches fileDate: Date) -> Bool {
        abs(cachedDate.timeIntervalSince(fileDate)) < 0.01
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

private struct CodexRolloutLine: Decodable {
    let timestamp: Date?
    let type: String?
    let payload: CodexRolloutPayload?
}

private struct CodexRolloutPayload: Decodable {
    let id: String?
    let originator: String?
    let cwd: String?
    let type: String?
    let role: String?
    let content: [CodexRolloutContent]?
}

private struct CodexRolloutContent: Decodable {
    let text: String?
}

private struct CodexSkillCandidate {
    let skillName: String
    let timestamp: Date
    let isExplicitTrigger: Bool
}
