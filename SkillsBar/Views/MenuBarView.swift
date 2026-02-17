import SwiftUI

private let claudeColor = Color(red: 0.85, green: 0.45, blue: 0.1)
private let codexColor = Color.purple
private let cardBackground = Color.primary.opacity(0.10)
private let cardRadius: CGFloat = 12

struct MenuBarView: View {
    @ObservedObject var store: SkillStore
    @ObservedObject var usageTracker: UsageTracker
    @State private var selectedSkill: Skill?
    @State private var selectedAgent: Agent?
    @State private var selectedTab: SkillStore.SkillTab = .claudeCode
    @State private var showAbout = false
    @State private var showUsageStats = false
    @State private var collapsedSections: Set<String> = {
        let saved = UserDefaults.standard.stringArray(forKey: "collapsedSections") ?? []
        return Set(saved)
    }()

    var body: some View {
        Group {
            if showAbout {
                AboutView(onBack: { showAbout = false })
            } else if showUsageStats {
                UsageStatsView(
                    usageTracker: usageTracker,
                    installedSkillNames: installedSkillTriggerNames,
                    onBack: { showUsageStats = false }
                )
            } else if let agent = selectedAgent {
                AgentDetailView(
                    agent: agent,
                    isPinned: store.isPinnedAgent(agent),
                    onBack: { selectedAgent = nil },
                    onDelete: { agent in
                        store.deleteAgent(agent)
                    },
                    onTogglePin: { agent in
                        store.togglePinAgent(agent)
                    }
                )
            } else if let skill = selectedSkill {
                SkillDetailView(
                    skill: skill,
                    isPinned: store.isPinned(skill),
                    usageStat: usageTracker.stat(for: skill.triggerCommand),
                    onBack: { selectedSkill = nil },
                    onDelete: { skill in
                        store.deleteSkill(skill)
                    },
                    onTogglePin: { skill in
                        store.togglePin(skill)
                    }
                )
            } else {
                mainListView
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var mainListView: some View {
        VStack(spacing: 8) {
            // Header
            HStack {
                Text("SkillsBar")
                    .font(.system(size: 16, weight: .bold))
                Spacer()
                Text("\(store.totalItemCount) skills & agents")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 2)

            // Tabs card
            HStack(spacing: 4) {
                ForEach(SkillStore.SkillTab.allCases) { tab in
                    tabButton(tab)
                }
            }
            .padding(4)
            .background(cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: cardRadius))
            .padding(.horizontal, 12)

            // Search card
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.tertiary)
                    .font(.system(size: 14))
                TextField("Search skills...", text: $store.searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                if !store.searchText.isEmpty {
                    Button(action: { store.searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                            .font(.system(size: 13))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(10)
            .background(cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: cardRadius))
            .padding(.horizontal, 12)

            // Content list
            contentListView

            // Footer card
            HStack {
                Button(action: {
                    store.refresh()
                    usageTracker.refresh()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12))
                        Text("Refresh")
                            .font(.system(size: 12))
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Refresh skills & stats")

                Spacer()

                Button(action: { showUsageStats = true }) {
                    HStack(spacing: 4) {
                        Image(systemName: "chart.bar")
                            .font(.system(size: 12))
                        Text("Stats")
                            .font(.system(size: 12))
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Usage statistics")

                Spacer()

                Text("⌥⇧S")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.tertiary)

                Spacer()

                Button(action: { showAbout = true }) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("About SkillsBar")

                Button(action: { NSApplication.shared.terminate(nil) }) {
                    Text("Quit")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: cardRadius))
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
        .frame(width: 440)
    }

    // MARK: - Content List

    private var contentListView: some View {
        let tabGroups = store.groupsForTab(selectedTab)
        let agentGroups = selectedTab == .claudeCode ? store.agentGroupsForTab() : []
        let hasContent = !tabGroups.isEmpty || !agentGroups.isEmpty

        return Group {
            if !hasContent {
                emptyStateView
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        if selectedTab == .claudeCode {
                            // Pinned sections first
                            ForEach(tabGroups.filter { $0.id == "pinned" }) { group in
                                ForEach(group.sections) { section in
                                    skillSectionCard(group: group, section: section)
                                }
                            }
                            ForEach(agentGroups.filter { $0.id == "pinned" }) { group in
                                ForEach(group.sections) { section in
                                    agentSectionCard(group: group, section: section)
                                }
                            }

                            // User Skills
                            ForEach(tabGroups.filter { $0.id != "pinned" }) { group in
                                ForEach(group.sections.filter { $0.id == "claude-user" }) { section in
                                    skillSectionCard(group: group, section: section)
                                }
                            }

                            // User Agents
                            ForEach(agentGroups.filter { $0.id != "pinned" }) { group in
                                ForEach(group.sections.filter { $0.id == "agent-user" }) { section in
                                    agentSectionCard(group: group, section: section)
                                }
                            }

                            // Plugin Skills
                            ForEach(tabGroups.filter { $0.id != "pinned" }) { group in
                                ForEach(group.sections.filter { $0.id == "claude-plugin" }) { section in
                                    skillSectionCard(group: group, section: section)
                                }
                            }

                            // Plugin Agents
                            ForEach(agentGroups.filter { $0.id != "pinned" }) { group in
                                ForEach(group.sections.filter { $0.id == "agent-plugin" }) { section in
                                    agentSectionCard(group: group, section: section)
                                }
                            }
                        } else {
                            // Codex tab - just skills
                            ForEach(tabGroups) { group in
                                ForEach(group.sections) { section in
                                    skillSectionCard(group: group, section: section)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                }
                .frame(maxHeight: 600)
            }
        }
    }

    // MARK: - Skill Section Card

    private func skillSectionCard(group: SkillGroup, section: SkillSection) -> some View {
        let collapsed = isSectionCollapsed(section.id)
        let showHeader = group.sections.count > 1 || group.id == "pinned"

        return VStack(alignment: .leading, spacing: 0) {
            if showHeader {
                Button(action: { withAnimation(.easeInOut(duration: 0.2)) { toggleSection(section.id) } }) {
                    HStack(spacing: 5) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.tertiary)
                            .rotationEffect(.degrees(collapsed ? 0 : 90))
                        if group.id == "pinned" {
                            Image(systemName: "star.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(.yellow)
                        }
                        Text(section.title.uppercased())
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .tracking(0.5)
                        if collapsed {
                            Text("\(section.skills.count)")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Color.secondary.opacity(0.12))
                                .clipShape(Capsule())
                        }
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, collapsed ? 8 : 4)
            }

            if !collapsed || !showHeader {
                ForEach(Array(section.skills.enumerated()), id: \.element.id) { index, skill in
                    if index > 0 {
                        Divider()
                            .padding(.leading, 44)
                    }
                    Button(action: { selectedSkill = skill }) {
                        SkillRowView(
                            skill: skill,
                            isPinned: store.isPinned(skill),
                            usageCount: usageTracker.stat(for: skill.triggerCommand)?.totalCount
                        )
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(store.isPinned(skill) ? "Unpin" : "Pin") {
                            store.togglePin(skill)
                        }
                        Divider()
                        Button("Open in VS Code") {
                            SkillStore.openInVSCode(skill)
                        }
                        Button("Open in Default Editor") {
                            SkillStore.openInDefaultEditor(skill)
                        }
                        Divider()
                        Button("Copy Command") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(skill.triggerCommand, forType: .string)
                        }
                        Button("Copy Path") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(skill.path, forType: .string)
                        }
                        Divider()
                        Button("Delete Skill", role: .destructive) {
                            store.deleteSkill(skill)
                        }
                    }
                }
            }
        }
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: cardRadius))
    }

    // MARK: - Agent Section Card

    private func agentSectionCard(group: AgentGroup, section: AgentSection) -> some View {
        let collapsed = isSectionCollapsed(section.id)

        return VStack(alignment: .leading, spacing: 0) {
            Button(action: { withAnimation(.easeInOut(duration: 0.2)) { toggleSection(section.id) } }) {
                HStack(spacing: 5) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(collapsed ? 0 : 90))
                    if group.id == "pinned" {
                        Image(systemName: "star.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.yellow)
                    }
                    Text(section.title.uppercased())
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .tracking(0.5)
                    if collapsed {
                        Text("\(section.agents.count)")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.12))
                            .clipShape(Capsule())
                    }
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, collapsed ? 8 : 4)

            if !collapsed {
                ForEach(Array(section.agents.enumerated()), id: \.element.id) { index, agent in
                    if index > 0 {
                        Divider()
                            .padding(.leading, 44)
                    }
                    Button(action: { selectedAgent = agent }) {
                        AgentRowView(
                            agent: agent,
                            isPinned: store.isPinnedAgent(agent)
                        )
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(store.isPinnedAgent(agent) ? "Unpin" : "Pin") {
                            store.togglePinAgent(agent)
                        }
                        Divider()
                        Button("Open in VS Code") {
                            SkillStore.openAgentInVSCode(agent)
                        }
                        Button("Open in Default Editor") {
                            SkillStore.openAgentInDefaultEditor(agent)
                        }
                        Divider()
                        Button("Copy Path") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(agent.path, forType: .string)
                        }
                        Divider()
                        Button("Delete Agent", role: .destructive) {
                            store.deleteAgent(agent)
                        }
                    }
                }
            }
        }
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: cardRadius))
    }

    // MARK: - Collapse Helpers

    private func isSectionCollapsed(_ id: String) -> Bool {
        collapsedSections.contains(id)
    }

    private func toggleSection(_ id: String) {
        if collapsedSections.contains(id) {
            collapsedSections.remove(id)
        } else {
            collapsedSections.insert(id)
        }
        UserDefaults.standard.set(Array(collapsedSections), forKey: "collapsedSections")
    }

    // MARK: - Tab Helpers

    private func tabColor(for tab: SkillStore.SkillTab) -> Color {
        switch tab {
        case .claudeCode: return claudeColor
        case .codex: return codexColor
        }
    }

    private func tabButton(_ tab: SkillStore.SkillTab) -> some View {
        let isSelected = selectedTab == tab
        let count = store.countForTab(tab)
        let color = tabColor(for: tab)

        return Button { selectedTab = tab } label: {
            HStack(spacing: 5) {
                Text(tab.rawValue)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                Text("\(count)")
                    .font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(isSelected ? color.opacity(0.2) : Color.secondary.opacity(0.1))
                    .clipShape(Capsule())
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity)
            .background(isSelected ? color.opacity(0.12) : Color.clear)
            .foregroundStyle(isSelected ? color : .secondary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 10) {
            if store.searchText.isEmpty {
                Image(systemName: "tray")
                    .font(.system(size: 28))
                    .foregroundStyle(.secondary)
                Text("No \(selectedTab.rawValue) skills found")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 6) {
                    Text(emptyStateHint)
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                    Text(emptyStatePath)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .textSelection(.enabled)
                }
                .padding(.top, 4)
            } else {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 28))
                    .foregroundStyle(.secondary)
                Text("No matching skills")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 48)
        .padding(.horizontal, 20)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: cardRadius))
        .padding(.horizontal, 12)
    }

    private var emptyStateHint: String {
        switch selectedTab {
        case .claudeCode:
            return "Create a skill folder with a SKILL.md file in:"
        case .codex:
            return "Install skills or create a folder with SKILL.md in:"
        }
    }

    private var emptyStatePath: String {
        switch selectedTab {
        case .claudeCode:
            return "~/.claude/skills/"
        case .codex:
            return "~/.codex/skills/"
        }
    }

    private var installedSkillTriggerNames: Set<String> {
        let allSkills = store.groups.flatMap { $0.sections.flatMap { $0.skills } }
        return Set(allSkills.map { skill in
            let cmd = skill.triggerCommand
            return cmd.hasPrefix("/") ? String(cmd.dropFirst()) : cmd
        })
    }
}
