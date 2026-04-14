import Foundation
import SwiftUI

@MainActor
final class SkillStore: ObservableObject {
    @Published var groups: [SkillGroup] = []
    @Published var agentGroups: [AgentGroup] = []
    @Published var plugins: [Plugin] = []
    @Published var collections: [SkillCollection] = []
    @Published var lastRefreshDate: Date?
    @Published var searchText: String = ""
    @Published var pinnedPaths: Set<String> = []
    @Published var pinnedOrder: [String] = []
    @Published var sortOption: SkillSortOption = .nameAsc {
        didSet {
            guard sortOption != oldValue else { return }
            UserDefaults.standard.set(sortOption.rawValue, forKey: Self.sortKey)
            refreshGroups()
        }
    }

    private var watcher: FSEventsWatcher?
    private var watchedRefreshPrefixes: [String] = []
    private var watchedCreationMarkers: Set<String> = []
    private var refreshGeneration: UInt64 = 0
    private var lastScannedSkills: [Skill] = []
    private var lastScannedAgents: [Agent] = []
    private(set) var usageTracker: UsageTracker?

    private static let pinnedKey = "pinnedSkillPaths"
    private static let pinnedOrderKey = "pinnedSkillOrder"
    private static let sortKey = "skillSortOption"
    private static let collectionsKey = "skillCollections"

    init(usageTracker: UsageTracker? = nil) {
        self.usageTracker = usageTracker
        if let raw = UserDefaults.standard.string(forKey: Self.sortKey),
           let saved = SkillSortOption(rawValue: raw) {
            self._sortOption = Published(initialValue: saved)
        }
        if let saved = UserDefaults.standard.stringArray(forKey: Self.pinnedKey) {
            pinnedPaths = Set(saved)
        }

        // Load or migrate pinned order
        if let savedOrder = UserDefaults.standard.stringArray(forKey: Self.pinnedOrderKey) {
            pinnedOrder = savedOrder.filter { pinnedPaths.contains($0) }
            let orderSet = Set(pinnedOrder)
            for path in pinnedPaths where !orderSet.contains(path) {
                pinnedOrder.append(path)
            }
        } else {
            pinnedOrder = Array(pinnedPaths).sorted()
        }

        if let savedData = UserDefaults.standard.data(forKey: Self.collectionsKey),
           let savedCollections = try? JSONDecoder().decode([SkillCollection].self, from: savedData) {
            collections = savedCollections
        }
    }

    private func persistPins() {
        UserDefaults.standard.set(Array(pinnedPaths), forKey: Self.pinnedKey)
        UserDefaults.standard.set(pinnedOrder, forKey: Self.pinnedOrderKey)
    }

    private func persistCollections() {
        let encoded = try? JSONEncoder().encode(collections)
        UserDefaults.standard.set(encoded, forKey: Self.collectionsKey)
    }

    func movePinnedItem(from sourcePath: String, toIndex destinationIndex: Int) {
        guard let sourceIndex = pinnedOrder.firstIndex(of: sourcePath) else { return }
        pinnedOrder.remove(at: sourceIndex)
        let adjustedIndex = min(destinationIndex, pinnedOrder.count)
        pinnedOrder.insert(sourcePath, at: adjustedIndex)
        persistPins()
    }

    // MARK: - Collections

    func createCollection(named name: String, including skill: Skill? = nil) -> SkillCollection {
        let collection = SkillCollection(
            name: uniqueCollectionName(from: name),
            skillPaths: skill.map { [$0.path] } ?? []
        )
        collections.append(collection)
        persistCollections()
        return collection
    }

    func renameCollection(_ collection: SkillCollection, to name: String) {
        guard let index = collections.firstIndex(where: { $0.id == collection.id }) else { return }
        collections[index].name = uniqueCollectionName(from: name, excluding: collection.id)
        collections[index].updatedAt = Date()
        persistCollections()
    }

    func deleteCollection(_ collection: SkillCollection) {
        collections.removeAll { $0.id == collection.id }
        persistCollections()
    }

    func toggleSkill(_ skill: Skill, in collection: SkillCollection) {
        guard let index = collections.firstIndex(where: { $0.id == collection.id }) else { return }

        if let pathIndex = collections[index].skillPaths.firstIndex(of: skill.path) {
            collections[index].skillPaths.remove(at: pathIndex)
        } else {
            collections[index].skillPaths.append(skill.path)
        }

        collections[index].updatedAt = Date()
        persistCollections()
    }

    func isSkill(_ skill: Skill, in collection: SkillCollection) -> Bool {
        collection.skillPaths.contains(skill.path)
    }

    func collections(for skill: Skill) -> [SkillCollection] {
        collections.filter { $0.skillPaths.contains(skill.path) }
    }

    func skill(forPath path: String) -> Skill? {
        lastScannedSkills.first { $0.path == path }
    }

    func resolvedCollections(searchText query: String = "") -> [ResolvedSkillCollection] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let skillLookup = Dictionary(uniqueKeysWithValues: lastScannedSkills.map { ($0.path, $0) })

        return collections.compactMap { collection in
            let resolvedSkills = collection.skillPaths.compactMap { skillLookup[$0] }
            let missingCount = max(0, collection.skillPaths.count - resolvedSkills.count)

            let visibleSkills: [Skill]
            if trimmedQuery.isEmpty {
                visibleSkills = resolvedSkills
            } else if collection.name.lowercased().contains(trimmedQuery) {
                visibleSkills = resolvedSkills
            } else {
                visibleSkills = resolvedSkills.filter { skill in
                    skill.name.lowercased().contains(trimmedQuery) ||
                    skill.description.lowercased().contains(trimmedQuery) ||
                    skill.triggerCommand.lowercased().contains(trimmedQuery) ||
                    skill.source.groupTitle.lowercased().contains(trimmedQuery) ||
                    skill.source.sectionTitle.lowercased().contains(trimmedQuery)
                }
            }

            let nameMatches = collection.name.lowercased().contains(trimmedQuery)
            guard trimmedQuery.isEmpty || nameMatches || !visibleSkills.isEmpty else { return nil }

            return ResolvedSkillCollection(
                collection: collection,
                skills: visibleSkills,
                missingCount: missingCount
            )
        }
    }

    private func uniqueCollectionName(from proposedName: String, excluding collectionID: UUID? = nil) -> String {
        let baseName = proposedName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "New Collection"
            : proposedName.trimmingCharacters(in: .whitespacesAndNewlines)

        let existingNames = Set(
            collections
                .filter { $0.id != collectionID }
                .map { $0.name.lowercased() }
        )

        guard !existingNames.contains(baseName.lowercased()) else {
            var suffix = 2
            while existingNames.contains("\(baseName) \(suffix)".lowercased()) {
                suffix += 1
            }
            return "\(baseName) \(suffix)"
        }

        return baseName
    }

    private func removeSkillPathFromCollections(_ path: String) {
        var didChange = false

        for index in collections.indices {
            let originalCount = collections[index].skillPaths.count
            collections[index].skillPaths.removeAll { $0 == path }
            if collections[index].skillPaths.count != originalCount {
                collections[index].updatedAt = Date()
                didChange = true
            }
        }

        if didChange {
            persistCollections()
        }
    }

    // MARK: - Pinning (Skills)

    func isPinned(_ skill: Skill) -> Bool {
        pinnedPaths.contains(skill.path)
    }

    func togglePin(_ skill: Skill) {
        if pinnedPaths.contains(skill.path) {
            pinnedPaths.remove(skill.path)
            pinnedOrder.removeAll { $0 == skill.path }
        } else {
            pinnedPaths.insert(skill.path)
            pinnedOrder.append(skill.path)
        }
        persistPins()
    }

    // MARK: - Pinning (Agents)

    func isPinnedAgent(_ agent: Agent) -> Bool {
        pinnedPaths.contains(agent.path)
    }

    func togglePinAgent(_ agent: Agent) {
        if pinnedPaths.contains(agent.path) {
            pinnedPaths.remove(agent.path)
            pinnedOrder.removeAll { $0 == agent.path }
        } else {
            pinnedPaths.insert(agent.path)
            pinnedOrder.append(agent.path)
        }
        persistPins()
    }

    // MARK: - Filtering (Skills)

    var filteredGroups: [SkillGroup] {
        guard !searchText.isEmpty else { return groups }
        let query = searchText.lowercased()

        return groups.compactMap { group in
            let filteredSections = group.sections.compactMap { section in
                let filtered = section.skills.filter { skill in
                    skill.name.lowercased().contains(query) ||
                    skill.description.lowercased().contains(query)
                }
                return filtered.isEmpty ? nil : SkillSection(id: section.id, title: section.title, skills: filtered)
            }
            return filteredSections.isEmpty ? nil : SkillGroup(id: group.id, title: group.title, sections: filteredSections)
        }
    }

    var totalSkillCount: Int {
        groups.reduce(0) { $0 + $1.totalCount }
    }

    var totalItemCount: Int {
        totalSkillCount + plugins.count + agentGroups.reduce(0) { $0 + $1.totalCount }
    }

    var filteredPlugins: [Plugin] {
        guard !searchText.isEmpty else { return plugins }
        let query = searchText.lowercased()

        return plugins.filter { plugin in
            plugin.displayName.lowercased().contains(query) ||
            plugin.name.lowercased().contains(query) ||
            plugin.description.lowercased().contains(query) ||
            plugin.shortDescription.lowercased().contains(query) ||
            (plugin.publisher?.lowercased().contains(query) ?? false) ||
            (plugin.version?.lowercased().contains(query) ?? false) ||
            plugin.keywords.contains(where: { $0.lowercased().contains(query) })
        }
    }

    func skills(for plugin: Plugin) -> [Skill] {
        let pluginPath = standardizedPath(plugin.path)
        let matchedSkills = lastScannedSkills.filter { skill in
            guard case .codexCLI(.plugin) = skill.source else { return false }
            return path(standardizedPath(skill.path), isEqualToOrInside: pluginPath)
        }
        return sortSkills(matchedSkills)
    }

    func groupsForTab(_ tab: SkillTab) -> [SkillGroup] {
        let source = filteredGroups
        var tabGroups: [SkillGroup]
        switch tab {
        case .claudeCode:
            tabGroups = source.filter { $0.id == "claude-code" }
        case .codex:
            tabGroups = source.filter { $0.id == "codex-cli" }
        case .collections:
            return []
        }

        // Build pinned section from skills in this tab, preserving custom order
        let allSkills = tabGroups.flatMap { $0.sections.flatMap { $0.skills } }
        let pinnedByPath = Dictionary(
            allSkills.filter { pinnedPaths.contains($0.path) }.map { ($0.path, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let pinned = pinnedOrder.compactMap { pinnedByPath[$0] }

        if !pinned.isEmpty {
            let pinnedPathSet = Set(pinned.map { $0.path })

            // Remove pinned skills from their original sections
            tabGroups = tabGroups.compactMap { group in
                let newSections = group.sections.compactMap { section in
                    let remaining = section.skills.filter { !pinnedPathSet.contains($0.path) }
                    return remaining.isEmpty ? nil : SkillSection(id: section.id, title: section.title, skills: remaining)
                }
                return newSections.isEmpty ? nil : SkillGroup(id: group.id, title: group.title, sections: newSections)
            }

            // Insert pinned group at top
            let pinnedSection = SkillSection(id: "pinned", title: "Pinned", skills: pinned)
            let pinnedGroup = SkillGroup(id: "pinned", title: "Pinned", sections: [pinnedSection])
            tabGroups.insert(pinnedGroup, at: 0)
        }

        return tabGroups
    }

    // MARK: - Filtering (Agents)

    var agentGroupsFiltered: [AgentGroup] {
        guard !searchText.isEmpty else { return agentGroups }
        let query = searchText.lowercased()

        return agentGroups.compactMap { group in
            let filteredSections = group.sections.compactMap { section in
                let filtered = section.agents.filter { agent in
                    agent.name.lowercased().contains(query) ||
                    agent.description.lowercased().contains(query)
                }
                return filtered.isEmpty ? nil : AgentSection(id: section.id, title: section.title, agents: filtered)
            }
            return filteredSections.isEmpty ? nil : AgentGroup(id: group.id, title: group.title, sections: filteredSections)
        }
    }

    func agentGroupsForTab() -> [AgentGroup] {
        let source = agentGroupsFiltered
        var tabGroups = source.filter { $0.id == "agents" }

        // Build pinned section from agents, preserving custom order
        let allAgents = tabGroups.flatMap { $0.sections.flatMap { $0.agents } }
        let pinnedAgentsByPath = Dictionary(
            allAgents.filter { pinnedPaths.contains($0.path) }.map { ($0.path, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let pinned = pinnedOrder.compactMap { pinnedAgentsByPath[$0] }

        if !pinned.isEmpty {
            let pinnedPathSet = Set(pinned.map { $0.path })

            tabGroups = tabGroups.compactMap { group in
                let newSections = group.sections.compactMap { section in
                    let remaining = section.agents.filter { !pinnedPathSet.contains($0.path) }
                    return remaining.isEmpty ? nil : AgentSection(id: section.id, title: section.title, agents: remaining)
                }
                return newSections.isEmpty ? nil : AgentGroup(id: group.id, title: group.title, sections: newSections)
            }

            let pinnedSection = AgentSection(id: "pinned", title: "Pinned", agents: pinned)
            let pinnedGroup = AgentGroup(id: "pinned", title: "Pinned", sections: [pinnedSection])
            tabGroups.insert(pinnedGroup, at: 0)
        }

        return tabGroups
    }

    func countForTab(_ tab: SkillTab) -> Int {
        let allGroups = groups
        switch tab {
        case .claudeCode:
            let skillCount = allGroups.filter { $0.id == "claude-code" }.reduce(0) { $0 + $1.totalCount }
            let agentCount = agentGroups.reduce(0) { $0 + $1.totalCount }
            return skillCount + agentCount
        case .codex:
            let skillCount = allGroups.filter { $0.id == "codex-cli" }.reduce(0) { $0 + $1.totalCount }
            return skillCount + plugins.count
        case .collections:
            return collections.count
        }
    }

    enum SkillTab: String, CaseIterable, Identifiable {
        case claudeCode = "Claude Code"
        case codex = "Codex"
        case collections = "Collections"

        var id: String { rawValue }
    }

    // MARK: - Lifecycle

    func start() {
        refresh()
        startWatching()
    }

    func refresh() {
        refreshGeneration += 1
        let generation = refreshGeneration

        Task(priority: .userInitiated) { [weak self] in
            let scanned = await Task.detached(priority: .userInitiated) {
                Self.scanContent()
            }.value

            guard let self else { return }
            guard generation == self.refreshGeneration else { return }

            self.lastScannedSkills = scanned.skills
            self.lastScannedAgents = scanned.agents
            self.groups = self.buildGroups(from: scanned.skills)
            self.agentGroups = self.buildAgentGroups(from: scanned.agents)
            self.plugins = scanned.plugins
            self.lastRefreshDate = Date()
        }
    }

    private func refreshGroups() {
        guard !lastScannedSkills.isEmpty else { return }
        groups = buildGroups(from: lastScannedSkills)
    }

    func deleteSkill(_ skill: Skill) {
        let fileManager = FileManager.default
        let skillDir = (skill.path as NSString).deletingLastPathComponent

        try? fileManager.removeItem(atPath: skillDir)
        pinnedPaths.remove(skill.path)
        pinnedOrder.removeAll { $0 == skill.path }
        persistPins()
        removeSkillPathFromCollections(skill.path)
        refresh()
    }

    func deleteAgent(_ agent: Agent) {
        let fileManager = FileManager.default
        try? fileManager.removeItem(atPath: agent.path)
        pinnedPaths.remove(agent.path)
        pinnedOrder.removeAll { $0 == agent.path }
        persistPins()
        refresh()
    }

    static func openInVSCode(_ skill: Skill) {
        let url = URL(fileURLWithPath: skill.path)
        NSWorkspace.shared.open(
            [url],
            withApplicationAt: URL(fileURLWithPath: "/Applications/Visual Studio Code.app"),
            configuration: NSWorkspace.OpenConfiguration()
        )
    }

    static func openInDefaultEditor(_ skill: Skill) {
        NSWorkspace.shared.open(URL(fileURLWithPath: skill.path))
    }

    static func revealInFinder(_ skill: Skill) {
        NSWorkspace.shared.selectFile(skill.path, inFileViewerRootedAtPath: "")
    }

    static func openAgentInVSCode(_ agent: Agent) {
        let url = URL(fileURLWithPath: agent.path)
        NSWorkspace.shared.open(
            [url],
            withApplicationAt: URL(fileURLWithPath: "/Applications/Visual Studio Code.app"),
            configuration: NSWorkspace.OpenConfiguration()
        )
    }

    static func openAgentInDefaultEditor(_ agent: Agent) {
        NSWorkspace.shared.open(URL(fileURLWithPath: agent.path))
    }

    static func revealAgentInFinder(_ agent: Agent) {
        NSWorkspace.shared.selectFile(agent.path, inFileViewerRootedAtPath: "")
    }

    static func openPluginInVSCode(_ plugin: Plugin) {
        let url = URL(fileURLWithPath: plugin.path)
        NSWorkspace.shared.open(
            [url],
            withApplicationAt: URL(fileURLWithPath: "/Applications/Visual Studio Code.app"),
            configuration: NSWorkspace.OpenConfiguration()
        )
    }

    static func openPluginInDefaultEditor(_ plugin: Plugin) {
        NSWorkspace.shared.open(URL(fileURLWithPath: plugin.path))
    }

    static func revealPluginInFinder(_ plugin: Plugin) {
        NSWorkspace.shared.selectFile(plugin.path, inFileViewerRootedAtPath: "")
    }

    // MARK: - Global Instructions Files

    enum GlobalInstructionsFile: String, CaseIterable, Identifiable {
        case claudeCode
        case codex

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .claudeCode: return "Global CLAUDE.md"
            case .codex:      return "Global AGENTS.md"
            }
        }

        var path: String {
            switch self {
            case .claudeCode: return ("~/.claude/CLAUDE.md" as NSString).expandingTildeInPath
            case .codex:      return ("~/.codex/AGENTS.md"  as NSString).expandingTildeInPath
            }
        }
    }

    static func openInstructionsFileInVSCode(_ file: GlobalInstructionsFile) {
        let url = URL(fileURLWithPath: file.path)
        NSWorkspace.shared.open(
            [url],
            withApplicationAt: URL(fileURLWithPath: "/Applications/Visual Studio Code.app"),
            configuration: NSWorkspace.OpenConfiguration()
        )
    }

    // MARK: - Watching

    private func startWatching() {
        watcher?.stop()

        let fileManager = FileManager.default
        let home = fileManager.homeDirectoryForCurrentUser.path
        let claudeRoot = (home as NSString).appendingPathComponent(".claude")
        let codexRoot = (home as NSString).appendingPathComponent(".codex")

        let targetPaths = [
            (home as NSString).appendingPathComponent(".claude/skills"),
            (home as NSString).appendingPathComponent(".claude/plugins/cache"),
            (home as NSString).appendingPathComponent(".claude/agents"),
            (home as NSString).appendingPathComponent(".codex/skills"),
            (home as NSString).appendingPathComponent(".codex/plugins/cache"),
        ].map { standardizedPath($0) }

        watchedRefreshPrefixes = targetPaths
        watchedCreationMarkers = []

        var watchPaths = targetPaths

        let claudeTargets = targetPaths.filter { path($0, isEqualToOrInside: standardizedPath(claudeRoot)) }
        if claudeTargets.contains(where: { !fileManager.fileExists(atPath: $0) }) {
            if fileManager.fileExists(atPath: claudeRoot) {
                watchPaths.append(standardizedPath(claudeRoot))
            } else {
                watchPaths.append(standardizedPath(home))
                watchedCreationMarkers.insert(standardizedPath(claudeRoot))
            }
        }

        let codexTargets = targetPaths.filter { path($0, isEqualToOrInside: standardizedPath(codexRoot)) }
        if codexTargets.contains(where: { !fileManager.fileExists(atPath: $0) }) {
            if fileManager.fileExists(atPath: codexRoot) {
                watchPaths.append(standardizedPath(codexRoot))
            } else {
                watchPaths.append(standardizedPath(home))
                watchedCreationMarkers.insert(standardizedPath(codexRoot))
            }
        }

        watchPaths = dedupePaths(watchPaths)

        watcher = FSEventsWatcher(paths: watchPaths) { [weak self] changedPaths in
            guard let self else { return }
            guard self.shouldRefresh(for: changedPaths) else { return }
            self.refresh()
        }
        watcher?.start()
    }

    private func shouldRefresh(for changedPaths: [String]) -> Bool {
        // Fall back to refreshing if event paths are unavailable.
        guard !changedPaths.isEmpty else { return true }

        for changedPath in changedPaths.map(standardizedPath) {
            if watchedCreationMarkers.contains(changedPath) {
                return true
            }

            if watchedRefreshPrefixes.contains(where: { path(changedPath, isEqualToOrInside: $0) }) {
                return true
            }
        }

        return false
    }

    private func standardizedPath(_ path: String) -> String {
        (path as NSString).standardizingPath
    }

    private func path(_ path: String, isEqualToOrInside base: String) -> Bool {
        path == base || path.hasPrefix(base + "/")
    }

    private func dedupePaths(_ paths: [String]) -> [String] {
        var seen: Set<String> = []
        var deduped: [String] = []

        for path in paths.map(standardizedPath) where seen.insert(path).inserted {
            deduped.append(path)
        }

        return deduped
    }

    nonisolated private static func scanContent() -> (skills: [Skill], agents: [Agent], plugins: [Plugin]) {
        let skills = SkillScanner().scanAll()
        let agents = AgentScanner().scanAll()
        let plugins = PluginScanner().scanInstalledPlugins()
        return (skills, agents, plugins)
    }

    // MARK: - Grouping (Skills)

    private func sortSkills(_ skills: [Skill]) -> [Skill] {
        switch sortOption {
        case .nameAsc:
            return skills.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .recentlyModified:
            return skills.sorted { a, b in
                switch (a.lastModified, b.lastModified) {
                case let (aDate?, bDate?):
                    return aDate > bDate
                case (_?, nil):
                    return true
                case (nil, _?):
                    return false
                case (nil, nil):
                    return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
                }
            }
        case .mostUsed:
            return skills.sorted { a, b in
                let aCount = usageTracker?.stat(for: a)?.totalCount ?? 0
                let bCount = usageTracker?.stat(for: b)?.totalCount ?? 0
                if aCount != bCount { return aCount > bCount }
                return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            }
        }
    }

    private func buildGroups(from skills: [Skill]) -> [SkillGroup] {
        var claudeUserSkills: [Skill] = []
        var claudePluginSkills: [Skill] = []
        var codexBuiltinSkills: [Skill] = []
        var codexPluginSkills: [Skill] = []
        var codexUserSkills: [Skill] = []

        for skill in skills {
            switch skill.source {
            case .claudeCode(.user): claudeUserSkills.append(skill)
            case .claudeCode(.plugin): claudePluginSkills.append(skill)
            case .codexCLI(.builtin): codexBuiltinSkills.append(skill)
            case .codexCLI(.plugin): codexPluginSkills.append(skill)
            case .codexCLI(.user): codexUserSkills.append(skill)
            }
        }

        var groups: [SkillGroup] = []

        let claudeSections = [
            claudeUserSkills.isEmpty ? nil : SkillSection(id: "claude-user", title: "User Skills", skills: sortSkills(claudeUserSkills)),
            claudePluginSkills.isEmpty ? nil : SkillSection(id: "claude-plugin", title: "Plugin Skills", skills: sortSkills(claudePluginSkills)),
        ].compactMap { $0 }

        if !claudeSections.isEmpty {
            groups.append(SkillGroup(id: "claude-code", title: "Claude Code", sections: claudeSections))
        }

        let codexSections = [
            codexUserSkills.isEmpty ? nil : SkillSection(id: "codex-user", title: "User Skills", skills: sortSkills(codexUserSkills)),
            codexPluginSkills.isEmpty ? nil : SkillSection(id: "codex-plugin", title: "Plugin Skills", skills: sortSkills(codexPluginSkills)),
            codexBuiltinSkills.isEmpty ? nil : SkillSection(id: "codex-builtin", title: "Built-in Skills", skills: sortSkills(codexBuiltinSkills)),
        ].compactMap { $0 }

        if !codexSections.isEmpty {
            groups.append(SkillGroup(id: "codex-cli", title: "Codex CLI", sections: codexSections))
        }

        return groups
    }

    // MARK: - Grouping (Agents)

    private func buildAgentGroups(from agents: [Agent]) -> [AgentGroup] {
        var userAgents: [Agent] = []
        var pluginAgents: [Agent] = []

        for agent in agents {
            switch agent.source {
            case .user: userAgents.append(agent)
            case .plugin: pluginAgents.append(agent)
            }
        }

        let sections = [
            userAgents.isEmpty ? nil : AgentSection(id: "agent-user", title: "User Agents", agents: userAgents.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }),
            pluginAgents.isEmpty ? nil : AgentSection(id: "agent-plugin", title: "Plugin Agents", agents: pluginAgents.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }),
        ].compactMap { $0 }

        if sections.isEmpty { return [] }
        return [AgentGroup(id: "agents", title: "Agents", sections: sections)]
    }
}
