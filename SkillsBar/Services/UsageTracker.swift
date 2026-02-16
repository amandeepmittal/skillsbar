import Foundation

private let iso8601WithFractional: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f
}()

private let iso8601Plain: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime]
    return f
}()

@MainActor
final class UsageTracker: ObservableObject {
    @Published var stats: [String: SkillUsageStat] = [:]
    @Published var isLoading = false
    @Published var lastRefreshDate: Date?

    private var autoRefreshTimer: Timer?
    private static let autoRefreshInterval: TimeInterval = 12 * 60 * 60 // 12 hours

    private let cacheURL: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("SkillsBar")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("usage-cache.json")
    }()

    // MARK: - Public API

    func stat(for triggerCommand: String) -> SkillUsageStat? {
        let normalized = triggerCommand.hasPrefix("/") ? String(triggerCommand.dropFirst()) : triggerCommand
        return stats[normalized]
    }

    var rankedStats: [SkillUsageStat] {
        stats.values.sorted { $0.totalCount > $1.totalCount }
    }

    var staleSkills: [SkillUsageStat] {
        stats.values.filter { $0.isStale }
    }

    var mostUsed: SkillUsageStat? {
        stats.values.max(by: { $0.totalCount < $1.totalCount })
    }

    var totalInvocations: Int {
        stats.values.reduce(0) { $0 + $1.totalCount }
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
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.path
        let projectsDir = "\(home)/.claude/projects"

        guard fm.fileExists(atPath: projectsDir) else {
            cache.lastFullScanDate = Date()
            return cache
        }

        // Collect all .jsonl files
        var jsonlFiles: [String] = []
        if let projectDirs = try? fm.contentsOfDirectory(atPath: projectsDir) {
            for projectDir in projectDirs {
                let projectPath = "\(projectsDir)/\(projectDir)"
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: projectPath, isDirectory: &isDir), isDir.boolValue else { continue }
                if let files = try? fm.contentsOfDirectory(atPath: projectPath) {
                    for file in files where file.hasSuffix(".jsonl") {
                        jsonlFiles.append("\(projectPath)/\(file)")
                    }
                }
            }
        }

        // Track which cached files still exist
        var validPaths = Set<String>()

        for filePath in jsonlFiles {
            validPaths.insert(filePath)

            guard let attrs = try? fm.attributesOfItem(atPath: filePath),
                  let mtime = attrs[.modificationDate] as? Date,
                  let size = attrs[.size] as? UInt64 else { continue }

            // Skip if unchanged
            if let cached = cache.parsedFiles[filePath],
               cached.lastModified == mtime,
               cached.fileSize == size {
                continue
            }

            // Parse the file
            let invocations = Self.parseSessionFile(at: filePath)
            cache.parsedFiles[filePath] = ParsedSessionFile(
                path: filePath,
                lastModified: mtime,
                fileSize: size,
                invocations: invocations
            )
        }

        // Prune deleted files
        for key in cache.parsedFiles.keys where !validPaths.contains(key) {
            cache.parsedFiles.removeValue(forKey: key)
        }

        cache.lastFullScanDate = Date()
        return cache
    }

    // MARK: - Parse Single File

    nonisolated private static func parseSessionFile(at path: String) -> [SkillInvocation] {
        var invocations: [SkillInvocation] = []
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let str = try container.decode(String.self)
            if let date = iso8601WithFractional.date(from: str) { return date }
            if let date = iso8601Plain.date(from: str) { return date }
            return Date.distantPast
        }

        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return [] }
        let lines = data.split(separator: UInt8(ascii: "\n"))

        // Extract project path from file path
        // ~/.claude/projects/<encoded-project-path>/<session>.jsonl
        let components = path.components(separatedBy: "/")
        let projectPath: String? = {
            if let idx = components.firstIndex(of: "projects"), idx + 1 < components.count {
                return components[idx + 1]
            }
            return nil
        }()

        let skillDirectoryPrefix = "Base directory for this skill:"

        for line in lines {
            guard let lineStr = String(data: Data(line), encoding: .utf8) else { continue }

            // Match 1: Skill tool_use (programmatic / agent invocations)
            if lineStr.contains("\"Skill\"") {
                if let sessionLine = try? decoder.decode(SessionLine.self, from: Data(line)),
                   sessionLine.type == "assistant",
                   let content = sessionLine.message?.content {
                    for block in content {
                        guard block.type == "tool_use",
                              block.name == "Skill",
                              let input = block.input,
                              let skillName = input.skill else { continue }

                        let timestamp = sessionLine.timestamp ?? Date.distantPast
                        invocations.append(SkillInvocation(
                            skillName: skillName,
                            args: input.args,
                            timestamp: timestamp,
                            sessionId: sessionLine.sessionId ?? "",
                            projectPath: projectPath
                        ))
                    }
                }
            }

            // Match 2: Skill expansion via /skill-name (user-typed slash commands)
            // These appear as type=user with text starting with "Base directory for this skill: <path>"
            if lineStr.contains(skillDirectoryPrefix) {
                if let sessionLine = try? decoder.decode(SessionLine.self, from: Data(line)),
                   sessionLine.type == "user",
                   let content = sessionLine.message?.content {
                    for block in content {
                        guard block.type == "text",
                              let text = block.text,
                              let range = text.range(of: skillDirectoryPrefix) else { continue }

                        // Extract skill name from path: "Base directory for this skill: ~/.claude/skills/<name>"
                        let pathStr = text[range.upperBound...].trimmingCharacters(in: .whitespaces)
                        let skillPath = pathStr.components(separatedBy: "\n").first ?? pathStr
                        let skillName = URL(fileURLWithPath: skillPath).lastPathComponent

                        guard !skillName.isEmpty else { continue }

                        let timestamp = sessionLine.timestamp ?? Date.distantPast
                        invocations.append(SkillInvocation(
                            skillName: skillName,
                            args: nil,
                            timestamp: timestamp,
                            sessionId: sessionLine.sessionId ?? "",
                            projectPath: projectPath
                        ))
                    }
                }
            }
        }

        return invocations
    }

    // MARK: - Build Stats

    nonisolated private static func buildStats(from cache: UsageCache) -> [String: SkillUsageStat] {
        var grouped: [String: [SkillInvocation]] = [:]

        for parsed in cache.parsedFiles.values {
            for invocation in parsed.invocations {
                let key = invocation.skillName
                grouped[key, default: []].append(invocation)
            }
        }

        var result: [String: SkillUsageStat] = [:]
        for (name, invocations) in grouped {
            let sorted = invocations.sorted { $0.timestamp < $1.timestamp }
            result[name] = SkillUsageStat(
                skillName: name,
                totalCount: invocations.count,
                lastUsedDate: sorted.last?.timestamp,
                firstUsedDate: sorted.first?.timestamp,
                invocations: sorted
            )
        }

        return result
    }

    // MARK: - Cache I/O

    nonisolated private func loadCache() async -> UsageCache {
        let url = await cacheURL
        guard let data = try? Data(contentsOf: url) else { return UsageCache() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let str = try container.decode(String.self)
            if let date = iso8601WithFractional.date(from: str) { return date }
            if let date = iso8601Plain.date(from: str) { return date }
            return Date.distantPast
        }
        return (try? decoder.decode(UsageCache.self, from: data)) ?? UsageCache()
    }

    nonisolated private func saveCache(_ cache: UsageCache) async {
        let url = await cacheURL
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(iso8601WithFractional.string(from: date))
        }
        guard let data = try? encoder.encode(cache) else { return }
        try? data.write(to: url, options: .atomic)
    }
}

// MARK: - Lightweight Decode Structs

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
