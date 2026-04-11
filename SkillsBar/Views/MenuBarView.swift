import SwiftUI

private let claudeColor = Color(red: 0.85, green: 0.45, blue: 0.1)
private let codexColor = Color.purple
private let collectionsColor = Color.blue
private let cardBackground = Color.primary.opacity(0.10)
private let cardRadius: CGFloat = 12

struct MenuBarView: View {
    @ObservedObject var store: SkillStore
    @ObservedObject var usageTracker: UsageTracker
    @State private var selectedSkill: Skill?
    @State private var selectedAgent: Agent?
    @State private var selectedPlugin: Plugin?
    @AppStorage("selectedTab") private var selectedTab: SkillStore.SkillTab = .claudeCode
    @State private var showAbout = false
    @State private var showUsageStats = false
    @State private var collapsedSections: Set<String> = {
        let saved = UserDefaults.standard.stringArray(forKey: "collapsedSections") ?? []
        return Set(saved)
    }()
    @State private var highlightedItemId: String?
    @State private var keyMonitor: Any?
    @State private var showingNewCollectionForm = false
    @State private var newCollectionName = ""
    @State private var pendingCollectionSkillPath: String?
    @State private var editingCollectionID: UUID?
    @State private var editingCollectionName = ""

    private enum ListItem {
        case skill(Skill)
        case agent(Agent)
        case plugin(Plugin)
        var id: String {
            switch self {
            case .skill(let s): return s.id
            case .agent(let a): return a.id
            case .plugin(let p): return p.id
            }
        }
    }

    var body: some View {
        Group {
            if showAbout {
                AboutView(skillStore: store, onBack: { showAbout = false })
            } else if showUsageStats {
                UsageStatsView(
                    usageTracker: usageTracker,
                    installedSkillIdentifiers: installedSkillIdentifiers,
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
            } else if let plugin = selectedPlugin {
                PluginDetailView(
                    plugin: plugin,
                    includedSkills: store.skills(for: plugin),
                    onBack: { selectedPlugin = nil },
                    onSelectSkill: { skill in
                        selectedPlugin = nil
                        selectedSkill = skill
                    }
                )
            } else if let skill = selectedSkill {
                SkillDetailView(
                    skill: skill,
                    isPinned: store.isPinned(skill),
                    usageStat: usageTracker.stat(for: skill),
                    collections: store.collections,
                    skillCollections: store.collections(for: skill),
                    onBack: { selectedSkill = nil },
                    onDelete: { skill in
                        store.deleteSkill(skill)
                    },
                    onTogglePin: { skill in
                        store.togglePin(skill)
                    },
                    onToggleCollectionMembership: { collection in
                        store.toggleSkill(skill, in: collection)
                    },
                    onCreateCollection: { skill in
                        startCreatingCollection(for: skill)
                    }
                )
            } else {
                mainListView
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            highlightedItemId = nil
            installKeyboardMonitor()
        }
        .onDisappear { removeKeyboardMonitor() }
        .onChange(of: selectedTab) { _, newTab in
            highlightedItemId = nil
            if newTab != .collections {
                resetCollectionComposer()
                editingCollectionID = nil
                editingCollectionName = ""
            }
        }
        .onChange(of: store.searchText) { _, _ in highlightedItemId = nil }
    }

    private var mainListView: some View {
        VStack(spacing: 8) {
            // Header
            HStack(spacing: 8) {
                Text("SkillsBar")
                    .font(.system(size: 16, weight: .bold))
                Text("⌥⇧S")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.tertiary)
                Spacer()
                Text("\(store.totalItemCount) items")
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
                TextField(searchPlaceholder, text: $store.searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .onExitCommand {
                        _ = clearSearch()
                    }
                if !store.searchText.isEmpty {
                    Button(action: { _ = clearSearch() }) {
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

                footerStatusView

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
        .frame(width: SkillsBarLayout.windowWidth)
    }

    // MARK: - Content List

    private var contentListView: some View {
        if selectedTab == .collections {
            return AnyView(collectionsListView)
        }

        let tabGroups = store.groupsForTab(selectedTab)
        let agentGroups = selectedTab == .claudeCode ? store.agentGroupsForTab() : []
        let plugins = selectedTab == .codex ? store.filteredPlugins : []
        let hasContent = !tabGroups.isEmpty || !agentGroups.isEmpty || !plugins.isEmpty

        return AnyView(Group {
            if !hasContent {
                emptyStateView
            } else {
                ScrollViewReader { scrollProxy in
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
                                // Pinned skills first
                                ForEach(tabGroups.filter { $0.id == "pinned" }) { group in
                                    ForEach(group.sections) { section in
                                        skillSectionCard(group: group, section: section)
                                    }
                                }

                                // User Skills
                                ForEach(tabGroups.filter { $0.id != "pinned" }) { group in
                                    ForEach(group.sections.filter { $0.id == "codex-user" }) { section in
                                        skillSectionCard(group: group, section: section)
                                    }
                                }

                                // Installed Plugins
                                if !plugins.isEmpty {
                                    pluginSectionCard(plugins)
                                }

                                // Plugin Skills
                                ForEach(tabGroups.filter { $0.id != "pinned" }) { group in
                                    ForEach(group.sections.filter { $0.id == "codex-plugin" }) { section in
                                        skillSectionCard(group: group, section: section)
                                    }
                                }

                                // Built-in Skills
                                ForEach(tabGroups.filter { $0.id != "pinned" }) { group in
                                    ForEach(group.sections.filter { $0.id == "codex-builtin" }) { section in
                                        skillSectionCard(group: group, section: section)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                    }
                    .frame(maxHeight: SkillsBarLayout.mainScrollHeight)
                    .onChange(of: highlightedItemId) { _, newValue in
                        if let id = newValue {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                scrollProxy.scrollTo(id, anchor: .center)
                            }
                        }
                    }
                }
            }
        })
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
                    skillRow(skill: skill, index: index, isPinned: group.id == "pinned", pinnedCount: section.skills.count)
                }
            }
        }
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: cardRadius))
    }

    private func skillRow(skill: Skill, index: Int, isPinned: Bool, pinnedCount: Int = 0) -> some View {
        Button(action: { selectedSkill = skill }) {
            SkillRowView(
                skill: skill,
                isPinned: store.isPinned(skill),
                usageCount: usageTracker.stat(for: skill)?.totalCount,
                showSourceBadge: selectedTab == .collections
            )
        }
        .buttonStyle(.plain)
        .background(highlightedItemId == skill.id ? Color.accentColor.opacity(0.12) : Color.clear)
        .onHover { hovering in
            if hovering { highlightedItemId = nil }
        }
        .id(skill.id)
        .contextMenu {
            Button(store.isPinned(skill) ? "Unpin" : "Pin") {
                store.togglePin(skill)
            }
            if isPinned && pinnedCount > 1 {
                Divider()
                if index > 0 {
                    Button("Move Up") {
                        store.movePinnedItem(from: skill.path, toIndex: index - 1)
                    }
                }
                if index < pinnedCount - 1 {
                    Button("Move Down") {
                        store.movePinnedItem(from: skill.path, toIndex: index + 1)
                    }
                }
            }
            Divider()
            if store.collections.isEmpty {
                Button("New Collection…") {
                    startCreatingCollection(for: skill)
                }
                Divider()
            } else {
                Menu("Collections") {
                    ForEach(store.collections) { collection in
                        Button(
                            store.isSkill(skill, in: collection)
                                ? "Remove from \(collection.name)"
                                : "Add to \(collection.name)"
                        ) {
                            store.toggleSkill(skill, in: collection)
                        }
                    }
                    Divider()
                    Button("New Collection…") {
                        startCreatingCollection(for: skill)
                    }
                }
                Divider()
            }
            Button("Open in VS Code") {
                SkillStore.openInVSCode(skill)
            }
            Button("Open in Default Editor") {
                SkillStore.openInDefaultEditor(skill)
            }
            Button("Reveal in Finder") {
                SkillStore.revealInFinder(skill)
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

    // MARK: - Plugin Section Card

    private func pluginSectionCard(_ plugins: [Plugin]) -> some View {
        let sectionID = "codex-installed-plugins"
        let collapsed = isSectionCollapsed(sectionID)

        return VStack(alignment: .leading, spacing: 0) {
            Button(action: { withAnimation(.easeInOut(duration: 0.2)) { toggleSection(sectionID) } }) {
                HStack(spacing: 5) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(collapsed ? 0 : 90))
                    Text("INSTALLED PLUGINS")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .tracking(0.5)
                    if collapsed {
                        Text("\(plugins.count)")
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
                ForEach(Array(plugins.enumerated()), id: \.element.id) { index, plugin in
                    if index > 0 {
                        Divider()
                            .padding(.leading, 44)
                    }
                    pluginRow(plugin: plugin)
                }
            }
        }
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: cardRadius))
    }

    private func pluginRow(plugin: Plugin) -> some View {
        Button(action: { selectedPlugin = plugin }) {
            PluginRowView(
                plugin: plugin,
                skillCount: store.skills(for: plugin).count
            )
        }
        .buttonStyle(.plain)
        .background(highlightedItemId == plugin.id ? Color.accentColor.opacity(0.12) : Color.clear)
        .onHover { hovering in
            if hovering { highlightedItemId = nil }
        }
        .id(plugin.id)
        .contextMenu {
            Button("Open in VS Code") {
                SkillStore.openPluginInVSCode(plugin)
            }
            Button("Open in Default Editor") {
                SkillStore.openPluginInDefaultEditor(plugin)
            }
            Button("Reveal in Finder") {
                SkillStore.revealPluginInFinder(plugin)
            }
            Divider()
            Button("Copy Path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(plugin.path, forType: .string)
            }
        }
    }

    // MARK: - Collections

    private var collectionsListView: some View {
        let resolvedCollections = store.resolvedCollections(searchText: store.searchText)
        let hasCollections = !store.collections.isEmpty

        return ScrollViewReader { scrollProxy in
            ScrollView {
                VStack(spacing: 8) {
                    collectionComposerCard

                    if !hasCollections {
                        collectionsEmptyStateView
                    } else if resolvedCollections.isEmpty {
                        collectionsSearchEmptyStateView
                    } else {
                        ForEach(resolvedCollections) { resolvedCollection in
                            collectionSectionCard(resolvedCollection)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
            }
            .frame(maxHeight: SkillsBarLayout.mainScrollHeight)
            .onChange(of: highlightedItemId) { _, newValue in
                if let id = newValue {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        scrollProxy.scrollTo(id, anchor: .center)
                    }
                }
            }
        }
    }

    private var collectionComposerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("COLLECTIONS")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .tracking(0.5)
                Spacer()
                if !showingNewCollectionForm {
                    Button {
                        showingNewCollectionForm = true
                        if newCollectionName.isEmpty {
                            newCollectionName = "New Collection"
                        }
                    } label: {
                        Label("New Collection", systemImage: "plus")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.blue)
                }
            }

            if showingNewCollectionForm {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Collection name", text: $newCollectionName)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(commitNewCollection)

                    if let pendingSkill = pendingCollectionSkill {
                        Text("\"\(pendingSkill.displayName)\" will be added after creation.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Mix Claude Code and Codex skills into one saved list.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 8) {
                        Button("Create", action: commitNewCollection)
                            .keyboardShortcut(.defaultAction)
                        Button("Cancel", action: resetCollectionComposer)
                    }
                }
            } else {
                Text("Build custom sets like Docs, Release, or Debugging across Claude Code and Codex.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: cardRadius))
    }

    private func collectionSectionCard(_ resolvedCollection: ResolvedSkillCollection) -> some View {
        let collection = resolvedCollection.collection
        let sectionID = collectionSectionID(for: collection)
        let collapsed = isSectionCollapsed(sectionID)
        let isEditing = editingCollectionID == collection.id

        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                if isEditing {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.tertiary)
                            .rotationEffect(.degrees(collapsed ? 0 : 90))
                        TextField("Collection name", text: $editingCollectionName)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { commitRenameCollection(collection) }
                        countBadge("\(resolvedCollection.skills.count)")
                        if resolvedCollection.missingCount > 0 {
                            countBadge("\(resolvedCollection.missingCount) missing", secondary: true)
                        }
                        Spacer()
                    }
                } else {
                    Button(action: { withAnimation(.easeInOut(duration: 0.2)) { toggleSection(sectionID) } }) {
                        HStack(spacing: 6) {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.tertiary)
                                .rotationEffect(.degrees(collapsed ? 0 : 90))
                            Text(collection.name.uppercased())
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .tracking(0.5)
                            countBadge("\(resolvedCollection.skills.count)")
                            if resolvedCollection.missingCount > 0 {
                                countBadge("\(resolvedCollection.missingCount) missing", secondary: true)
                            }
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                if isEditing {
                    Button("Save") {
                        commitRenameCollection(collection)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.blue)

                    Button("Cancel") {
                        editingCollectionID = nil
                        editingCollectionName = ""
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                } else {
                    Menu {
                        Button("Rename") {
                            editingCollectionID = collection.id
                            editingCollectionName = collection.name
                        }
                        Button("Delete Collection", role: .destructive) {
                            store.deleteCollection(collection)
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, collapsed ? 10 : 6)

            if !collapsed {
                if resolvedCollection.skills.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("No available skills in this collection right now.")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                        if resolvedCollection.missingCount > 0 {
                            Text("Some saved skills could not be resolved from the current scan.")
                                .font(.system(size: 12))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                } else {
                    ForEach(Array(resolvedCollection.skills.enumerated()), id: \.element.id) { index, skill in
                        if index > 0 {
                            Divider()
                                .padding(.leading, 44)
                        }
                        skillRow(skill: skill, index: index, isPinned: false)
                    }
                }
            }
        }
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: cardRadius))
    }

    private var collectionsEmptyStateView: some View {
        VStack(spacing: 10) {
            Image(systemName: "square.stack.3d.up")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text("No collections yet")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
            Text("Create a collection to group Claude Code and Codex skills together.")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: cardRadius))
    }

    private var collectionsSearchEmptyStateView: some View {
        VStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text("No matching collections")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
            Text("Try a collection name, skill name, or trigger command.")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: cardRadius))
    }

    private var pendingCollectionSkill: Skill? {
        guard let pendingCollectionSkillPath else { return nil }
        return store.skill(forPath: pendingCollectionSkillPath)
    }

    private func startCreatingCollection(for skill: Skill? = nil) {
        selectedSkill = nil
        selectedAgent = nil
        selectedPlugin = nil
        showAbout = false
        showUsageStats = false
        selectedTab = .collections
        showingNewCollectionForm = true
        newCollectionName = skill.map { "\($0.displayName)" } ?? "New Collection"
        pendingCollectionSkillPath = skill?.path
    }

    private func resetCollectionComposer() {
        showingNewCollectionForm = false
        newCollectionName = ""
        pendingCollectionSkillPath = nil
    }

    private func commitNewCollection() {
        let skill = pendingCollectionSkill
        _ = store.createCollection(named: newCollectionName, including: skill)
        resetCollectionComposer()
    }

    private func commitRenameCollection(_ collection: SkillCollection) {
        store.renameCollection(collection, to: editingCollectionName)
        editingCollectionID = nil
        editingCollectionName = ""
    }

    private func collectionSectionID(for collection: SkillCollection) -> String {
        "collection-\(collection.id.uuidString)"
    }

    private func countBadge(_ text: String, secondary: Bool = false) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(secondary ? .tertiary : .secondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(Color.secondary.opacity(secondary ? 0.08 : 0.12))
            .clipShape(Capsule())
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
                    agentRow(agent: agent, index: index, isPinned: group.id == "pinned", pinnedCount: section.agents.count)
                }
            }
        }
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: cardRadius))
    }

    private func agentRow(agent: Agent, index: Int, isPinned: Bool, pinnedCount: Int = 0) -> some View {
        Button(action: { selectedAgent = agent }) {
            AgentRowView(
                agent: agent,
                isPinned: store.isPinnedAgent(agent)
            )
        }
        .buttonStyle(.plain)
        .background(highlightedItemId == agent.id ? Color.accentColor.opacity(0.12) : Color.clear)
        .onHover { hovering in
            if hovering { highlightedItemId = nil }
        }
        .id(agent.id)
        .contextMenu {
            Button(store.isPinnedAgent(agent) ? "Unpin" : "Pin") {
                store.togglePinAgent(agent)
            }
            if isPinned && pinnedCount > 1 {
                Divider()
                if index > 0 {
                    Button("Move Up") {
                        store.movePinnedItem(from: agent.path, toIndex: index - 1)
                    }
                }
                if index < pinnedCount - 1 {
                    Button("Move Down") {
                        store.movePinnedItem(from: agent.path, toIndex: index + 1)
                    }
                }
            }
            Divider()
            Button("Open in VS Code") {
                SkillStore.openAgentInVSCode(agent)
            }
            Button("Open in Default Editor") {
                SkillStore.openAgentInDefaultEditor(agent)
            }
            Button("Reveal in Finder") {
                SkillStore.revealAgentInFinder(agent)
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
        case .collections: return collectionsColor
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
                Text(emptyStateTitle)
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
                Text(searchEmptyStateTitle)
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
            return "Install a plugin or create a folder with SKILL.md in:"
        case .collections:
            return "Create a collection to group skills across Claude Code and Codex."
        }
    }

    private var emptyStateTitle: String {
        switch selectedTab {
        case .claudeCode:
            return "No Claude Code skills found"
        case .codex:
            return "No Codex items found"
        case .collections:
            return "No collections found"
        }
    }

    private var searchEmptyStateTitle: String {
        switch selectedTab {
        case .codex:
            return "No matching skills or plugins"
        case .claudeCode:
            return "No matching skills"
        case .collections:
            return "No matching collections"
        }
    }

    private var emptyStatePath: String {
        switch selectedTab {
        case .claudeCode:
            return "~/.claude/skills/"
        case .codex:
            return "~/.codex/skills/\n~/.codex/plugins/cache/"
        case .collections:
            return "Use the New Collection button above."
        }
    }

    private var searchPlaceholder: String {
        switch selectedTab {
        case .collections:
            return "Search collections or skills..."
        case .claudeCode:
            return "Search skills..."
        case .codex:
            return "Search skills or plugins..."
        }
    }

    private var footerLastRefreshDate: Date? {
        [store.lastRefreshDate, usageTracker.lastRefreshDate]
            .compactMap { $0 }
            .max()
    }

    @ViewBuilder
    private var footerStatusView: some View {
        if let footerLastRefreshDate {
            TimelineView(.periodic(from: footerLastRefreshDate, by: 60)) { context in
                Text(refreshStatusText(since: footerLastRefreshDate, now: context.date))
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func refreshStatusText(since date: Date, now: Date) -> String {
        let elapsed = max(0, now.timeIntervalSince(date))

        if elapsed < 5 * 60 {
            return "Updated just now"
        }
        if elapsed < 60 * 60 {
            return "Updated \(Int(elapsed / 60))m ago"
        }
        if elapsed < 24 * 60 * 60 {
            return "Updated \(Int(elapsed / 3600))h ago"
        }

        return "Updated \(date.formatted(date: .abbreviated, time: .shortened))"
    }

    // MARK: - Keyboard Navigation

    private var flatVisibleItems: [ListItem] {
        var items: [ListItem] = []
        if selectedTab == .collections {
            for resolvedCollection in store.resolvedCollections(searchText: store.searchText) {
                let sectionID = collectionSectionID(for: resolvedCollection.collection)
                if !isSectionCollapsed(sectionID) {
                    items.append(contentsOf: resolvedCollection.skills.map { .skill($0) })
                }
            }
            return items
        }

        let tabGroups = store.groupsForTab(selectedTab)
        let agentGroups = selectedTab == .claudeCode ? store.agentGroupsForTab() : []
        let plugins = selectedTab == .codex ? store.filteredPlugins : []

        func addSkills(from groups: [SkillGroup], groupFilter: (SkillGroup) -> Bool, sectionFilter: ((SkillSection) -> Bool)? = nil) {
            for group in groups where groupFilter(group) {
                let sections = sectionFilter != nil ? group.sections.filter(sectionFilter!) : group.sections
                for section in sections {
                    let showHeader = group.sections.count > 1 || group.id == "pinned"
                    if !isSectionCollapsed(section.id) || !showHeader {
                        items.append(contentsOf: section.skills.map { .skill($0) })
                    }
                }
            }
        }

        func addAgents(from groups: [AgentGroup], groupFilter: (AgentGroup) -> Bool, sectionFilter: ((AgentSection) -> Bool)? = nil) {
            for group in groups where groupFilter(group) {
                let sections = sectionFilter != nil ? group.sections.filter(sectionFilter!) : group.sections
                for section in sections {
                    if !isSectionCollapsed(section.id) {
                        items.append(contentsOf: section.agents.map { .agent($0) })
                    }
                }
            }
        }

        if selectedTab == .claudeCode {
            addSkills(from: tabGroups, groupFilter: { $0.id == "pinned" })
            addAgents(from: agentGroups, groupFilter: { $0.id == "pinned" })
            addSkills(from: tabGroups, groupFilter: { $0.id != "pinned" }, sectionFilter: { $0.id == "claude-user" })
            addAgents(from: agentGroups, groupFilter: { $0.id != "pinned" }, sectionFilter: { $0.id == "agent-user" })
            addSkills(from: tabGroups, groupFilter: { $0.id != "pinned" }, sectionFilter: { $0.id == "claude-plugin" })
            addAgents(from: agentGroups, groupFilter: { $0.id != "pinned" }, sectionFilter: { $0.id == "agent-plugin" })
        } else {
            addSkills(from: tabGroups, groupFilter: { $0.id == "pinned" })
            addSkills(from: tabGroups, groupFilter: { $0.id != "pinned" }, sectionFilter: { $0.id == "codex-user" })
            if !isSectionCollapsed("codex-installed-plugins") {
                items.append(contentsOf: plugins.map { .plugin($0) })
            }
            addSkills(from: tabGroups, groupFilter: { $0.id != "pinned" }, sectionFilter: { $0.id == "codex-plugin" })
            addSkills(from: tabGroups, groupFilter: { $0.id != "pinned" }, sectionFilter: { $0.id == "codex-builtin" })
        }

        return items
    }

    private func installKeyboardMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [self] event in
            handleKeyEvent(event)
        }
    }

    private func removeKeyboardMonitor() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
    }

    private func handleKeyEvent(_ event: NSEvent) -> NSEvent? {
        let isOnMainList = selectedSkill == nil && selectedAgent == nil && selectedPlugin == nil && !showAbout && !showUsageStats

        switch Int(event.keyCode) {
        case 123: // Left arrow
            guard event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command) else {
                return event
            }
            return handleBackNavigation() ? nil : event
        case 125: // Down arrow
            guard isOnMainList else { return event }
            moveHighlight(by: 1)
            return nil
        case 126: // Up arrow
            guard isOnMainList else { return event }
            moveHighlight(by: -1)
            return nil
        case 36: // Return
            guard isOnMainList, highlightedItemId != nil else { return event }
            openHighlightedItem()
            return nil
        case 53: // Escape
            return handleEscape() ? nil : event
        default:
            return event
        }
    }

    private func moveHighlight(by offset: Int) {
        let items = flatVisibleItems
        guard !items.isEmpty else { return }

        if let currentId = highlightedItemId,
           let currentIndex = items.firstIndex(where: { $0.id == currentId }) {
            let newIndex = max(0, min(items.count - 1, currentIndex + offset))
            highlightedItemId = items[newIndex].id
        } else {
            highlightedItemId = offset > 0 ? items.first?.id : items.last?.id
        }
    }

    private func openHighlightedItem() {
        guard let id = highlightedItemId else { return }
        let items = flatVisibleItems
        guard let item = items.first(where: { $0.id == id }) else { return }
        switch item {
        case .skill(let skill): selectedSkill = skill
        case .agent(let agent): selectedAgent = agent
        case .plugin(let plugin): selectedPlugin = plugin
        }
    }

    private func handleBackNavigation() -> Bool {
        if selectedSkill != nil {
            selectedSkill = nil
            return true
        }
        if selectedAgent != nil {
            selectedAgent = nil
            return true
        }
        if selectedPlugin != nil {
            selectedPlugin = nil
            return true
        }
        if showAbout {
            showAbout = false
            return true
        }
        if showUsageStats {
            showUsageStats = false
            return true
        }
        return false
    }

    private func handleEscape() -> Bool {
        if handleBackNavigation() {
            return true
        }
        return clearSearch()
    }

    @discardableResult
    private func clearSearch() -> Bool {
        guard !store.searchText.isEmpty else { return false }
        store.searchText = ""
        return true
    }

    private var installedSkillIdentifiers: Set<String> {
        let allSkills = store.groups.flatMap { $0.sections.flatMap { $0.skills } }
        return Set(allSkills.map { UsageTracker.identifier(for: $0) })
    }
}
