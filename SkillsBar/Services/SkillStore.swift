import Foundation
import SwiftUI

@MainActor
final class SkillStore: ObservableObject {
    @Published var groups: [SkillGroup] = []
    @Published var agentGroups: [AgentGroup] = []
    @Published var searchText: String = ""
    @Published var pinnedPaths: Set<String> = []
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
    private static let sortKey = "skillSortOption"

    init(usageTracker: UsageTracker? = nil) {
        self.usageTracker = usageTracker
        if let raw = UserDefaults.standard.string(forKey: Self.sortKey),
           let saved = SkillSortOption(rawValue: raw) {
            self._sortOption = Published(initialValue: saved)
        }
        if let saved = UserDefaults.standard.stringArray(forKey: Self.pinnedKey) {
            pinnedPaths = Set(saved)
        }
    }

    // MARK: - Pinning (Skills)

    func isPinned(_ skill: Skill) -> Bool {
        pinnedPaths.contains(skill.path)
    }

    func togglePin(_ skill: Skill) {
        if pinnedPaths.contains(skill.path) {
            pinnedPaths.remove(skill.path)
        } else {
            pinnedPaths.insert(skill.path)
        }
        UserDefaults.standard.set(Array(pinnedPaths), forKey: Self.pinnedKey)
    }

    // MARK: - Pinning (Agents)

    func isPinnedAgent(_ agent: Agent) -> Bool {
        pinnedPaths.contains(agent.path)
    }

    func togglePinAgent(_ agent: Agent) {
        if pinnedPaths.contains(agent.path) {
            pinnedPaths.remove(agent.path)
        } else {
            pinnedPaths.insert(agent.path)
        }
        UserDefaults.standard.set(Array(pinnedPaths), forKey: Self.pinnedKey)
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
        totalSkillCount + agentGroups.reduce(0) { $0 + $1.totalCount }
    }

    func groupsForTab(_ tab: SkillTab) -> [SkillGroup] {
        let source = filteredGroups
        var tabGroups: [SkillGroup]
        switch tab {
        case .claudeCode:
            tabGroups = source.filter { $0.id == "claude-code" }
        case .codex:
            tabGroups = source.filter { $0.id == "codex-cli" }
        }

        // Build pinned section from skills in this tab
        let allSkills = tabGroups.flatMap { $0.sections.flatMap { $0.skills } }
        let pinned = allSkills.filter { pinnedPaths.contains($0.path) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

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

        // Build pinned section from agents
        let allAgents = tabGroups.flatMap { $0.sections.flatMap { $0.agents } }
        let pinned = allAgents.filter { pinnedPaths.contains($0.path) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

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
            return allGroups.filter { $0.id == "codex-cli" }.reduce(0) { $0 + $1.totalCount }
        }
    }

    enum SkillTab: String, CaseIterable, Identifiable {
        case claudeCode = "Claude Code"
        case codex = "Codex"

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
                Self.scanSkillsAndAgents()
            }.value

            guard let self else { return }
            guard generation == self.refreshGeneration else { return }

            self.lastScannedSkills = scanned.skills
            self.lastScannedAgents = scanned.agents
            self.groups = self.buildGroups(from: scanned.skills)
            self.agentGroups = self.buildAgentGroups(from: scanned.agents)
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
        UserDefaults.standard.set(Array(pinnedPaths), forKey: Self.pinnedKey)
        refresh()
    }

    func deleteAgent(_ agent: Agent) {
        let fileManager = FileManager.default
        try? fileManager.removeItem(atPath: agent.path)
        pinnedPaths.remove(agent.path)
        UserDefaults.standard.set(Array(pinnedPaths), forKey: Self.pinnedKey)
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

    nonisolated private static func scanSkillsAndAgents() -> (skills: [Skill], agents: [Agent]) {
        let skills = SkillScanner().scanAll()
        let agents = AgentScanner().scanAll()
        return (skills, agents)
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
                let aCount = usageTracker?.stat(for: a.triggerCommand)?.totalCount ?? 0
                let bCount = usageTracker?.stat(for: b.triggerCommand)?.totalCount ?? 0
                if aCount != bCount { return aCount > bCount }
                return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            }
        }
    }

    private func buildGroups(from skills: [Skill]) -> [SkillGroup] {
        var claudeUserSkills: [Skill] = []
        var claudePluginSkills: [Skill] = []
        var codexBuiltinSkills: [Skill] = []
        var codexUserSkills: [Skill] = []

        for skill in skills {
            switch skill.source {
            case .claudeCode(.user): claudeUserSkills.append(skill)
            case .claudeCode(.plugin): claudePluginSkills.append(skill)
            case .codexCLI(.builtin): codexBuiltinSkills.append(skill)
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
