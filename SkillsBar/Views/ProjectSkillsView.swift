import AppKit
import SwiftUI
import UniformTypeIdentifiers

private let projectRecentWindow: TimeInterval = 7 * 24 * 60 * 60

struct ProjectSkillsView: View {
    @ObservedObject var skillStore: SkillStore
    let onBack: () -> Void

    @AppStorage(AppPreferenceKey.preferredEditor) private var preferredEditorRaw = ExternalEditor.visualStudioCode.rawValue
    @State private var pendingProjectRoot: ProjectSkillRoot?
    @State private var pendingProjectSkillCount: Int?
    @State private var selectedProjectRootID: UUID?
    @State private var editingProjectRootID: UUID?
    @State private var editingProjectName = ""
    @State private var draggingProjectRootID: UUID?
    @State private var projectSearchText = ""
    @State private var actionMessage: String?
    @State private var actionDismissWorkItem: DispatchWorkItem?

    private let cardRadius: CGFloat = 12
    private let cardBackground = Color.primary.opacity(0.10)
    private let fileManager = FileManager.default

    var body: some View {
        ZStack(alignment: .bottom) {
            if let selectedProjectRoot {
                projectDetailView(selectedProjectRoot)
            } else {
                projectListView
            }

            if let actionMessage {
                Text(actionMessage)
                    .font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.regularMaterial)
                    .clipShape(Capsule())
                    .shadow(radius: 6)
                    .padding(.bottom, 14)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(width: SkillsBarLayout.windowWidth, height: SkillsBarLayout.aboutHeight)
        .onDisappear {
            actionDismissWorkItem?.cancel()
            actionDismissWorkItem = nil
        }
    }

    private var selectedProjectRoot: ProjectSkillRoot? {
        guard let selectedProjectRootID else { return nil }
        return skillStore.projectSkillRoots.first { $0.id == selectedProjectRootID }
    }

    private var projectListView: some View {
        VStack(spacing: 0) {
            header(title: "Project Skills", showsAddButton: true, backAction: onBack)

            Divider()

            ScrollView {
                VStack(spacing: 10) {
                    projectListCard

                    if !allProjectConflicts.isEmpty {
                        projectConflictCenterCard(conflicts: allProjectConflicts)
                    }

                    if let pendingProjectRoot, let pendingProjectSkillCount {
                        projectRootPreview(root: pendingProjectRoot, skillCount: pendingProjectSkillCount)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .top)
            }
        }
    }

    private func header(title: String, showsAddButton: Bool, backAction: @escaping () -> Void) -> some View {
        HStack {
            Button(action: backAction) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Back")
                        .font(.system(size: 14))
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.blue)

            Spacer()

            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .lineLimit(1)

            Spacer()

            if showsAddButton {
                Button(action: chooseProjectRoot) {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 44, height: 20, alignment: .trailing)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.blue)
                .help("Add Project")
            } else {
                Color.clear
                    .frame(width: 44, height: 20)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private var projectListCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text("APPROVED PROJECTS")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .tracking(0.5)
                countBadge("\(skillStore.projectSkillRoots.count)")
                if pinnedProjectRoots.count > 0 {
                    countBadge("\(pinnedProjectRoots.count) pinned", tint: .yellow)
                }
                Spacer()
                Button(action: chooseProjectRoot) {
                    Label("Add", systemImage: "plus")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.blue)
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, skillStore.projectSkillRoots.isEmpty ? 8 : 4)

            if skillStore.projectSkillRoots.isEmpty {
                emptyProjectsView
            } else {
                ForEach(Array(skillStore.orderedProjectSkillRoots.enumerated()), id: \.element.id) { index, root in
                    if index > 0 {
                        sectionDivider
                    }
                    projectRootRow(root)
                        .onDrag {
                            draggingProjectRootID = root.id
                            return NSItemProvider(object: root.id.uuidString as NSString)
                        }
                        .onDrop(
                            of: [UTType.text],
                            delegate: ProjectRootDropDelegate(
                                targetRoot: root,
                                skillStore: skillStore,
                                draggingProjectRootID: $draggingProjectRootID
                            )
                        )
                }
            }
        }
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: cardRadius))
    }

    private var emptyProjectsView: some View {
        VStack(spacing: 10) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text("No projects added")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
            Button(action: chooseProjectRoot) {
                Label("Add Project", systemImage: "plus")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.blue)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }

    private func projectRootRow(_ root: ProjectSkillRoot) -> some View {
        let status = skillStore.projectSkillRootStatus(for: root)
        let skillCount = skillStore.projectSkillCount(for: root)
        let agentCount = skillStore.projectAgents(for: root).count
        let instructionCount = skillStore.projectInstructions(for: root).count
        let conflicts = skillStore.projectConflicts(for: root)
        let trustStatus = skillStore.projectTrustStatus(for: root)
        let recentCount = recentItems(for: root).count
        let changedSinceScan = changedSinceLastScan(for: root)
        let isEditing = editingProjectRootID == root.id

        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: projectRootIcon(for: status))
                .font(.system(size: 12))
                .foregroundStyle(projectRootTint(for: status))
                .frame(width: 18, height: 18)
                .padding(.top, 2)

            Button {
                selectedProjectRootID = root.id
                projectSearchText = ""
            } label: {
                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 6) {
                        if isEditing {
                            TextField("Project name", text: $editingProjectName)
                                .textFieldStyle(.roundedBorder)
                                .onSubmit { commitProjectRename(root) }
                        } else {
                            Text(root.name)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                        }

                        if root.isPinned {
                            Image(systemName: "star.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(.yellow)
                        }

                        projectRootBadge(status.title, tint: projectRootTint(for: status))

                        if status == .available {
                            projectRootBadge(projectSkillCountLabel(skillCount), tint: .secondary, secondary: true)
                        }

                        if agentCount > 0 {
                            projectRootBadge(projectAgentCountLabel(agentCount), tint: .cyan, secondary: true)
                        }

                        if instructionCount > 0 {
                            projectRootBadge("\(instructionCount) instructions", tint: .purple, secondary: true)
                        }
                    }

                    Text(abbreviatedPath(root.path))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .textSelection(.enabled)

                    HStack(spacing: 6) {
                        ForEach(healthBadges(for: root, status: status, skillCount: skillCount, conflicts: conflicts, recentCount: recentCount, changedSinceScan: changedSinceScan, trustStatus: trustStatus), id: \.label) { badge in
                            projectRootBadge(badge.label, tint: badge.tint, secondary: badge.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isEditing {
                Button("Save") {
                    commitProjectRename(root)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.blue)

                Button("Cancel") {
                    editingProjectRootID = nil
                    editingProjectName = ""
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            } else {
                Toggle("", isOn: Binding(
                    get: { root.isEnabled },
                    set: { skillStore.setProjectSkillRoot(root, isEnabled: $0) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)

                projectRootMenu(root: root, status: status, skillCount: skillCount, trustStatus: trustStatus)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func projectRootMenu(
        root: ProjectSkillRoot,
        status: ProjectSkillRootStatus,
        skillCount: Int,
        trustStatus: ProjectTrustStatus
    ) -> some View {
        Menu {
            Button(root.isPinned ? "Unpin Project" : "Pin Project") {
                skillStore.togglePinProjectSkillRoot(root)
            }
            Button("Rename") {
                editingProjectRootID = root.id
                editingProjectName = root.name
            }
            if skillStore.canMoveProjectSkillRoot(root, by: -1) {
                Button("Move Up") {
                    skillStore.moveProjectSkillRoot(root, by: -1)
                }
            }
            if skillStore.canMoveProjectSkillRoot(root, by: 1) {
                Button("Move Down") {
                    skillStore.moveProjectSkillRoot(root, by: 1)
                }
            }
            Divider()
            Button("Create Collection from Project") {
                createCollection(from: root)
            }
            .disabled(skillCount == 0)
            Button("Trust Current Project Files") {
                skillStore.trustCurrentProjectContent(for: root)
                showActionMessage("Project files trusted")
            }
            .disabled(!trustStatus.needsAction)
            if status == .missingSkillsFolder {
                Button("Create .claude/skills Folder") {
                    createProjectSkillsFolder(for: root)
                }
            }
            Divider()
            Button("Refresh Skills") {
                skillStore.refresh()
            }
            Button(preferredEditor.openMenuTitle) {
                SkillStore.openProject(root, in: preferredEditor)
            }
            Button("Open in Claude Code") {
                SkillStore.openProjectInClaudeCode(root)
            }
            Button("Open in Codex") {
                SkillStore.openProjectInCodex(root)
            }
            Button("Open .claude/skills") {
                SkillStore.openProjectSkillsFolder(root, in: preferredEditor)
            }
            .disabled(status == .missingProjectFolder || status == .missingSkillsFolder)
            Button("Open .claude/agents") {
                SkillStore.openProjectAgentsFolder(root, in: preferredEditor)
            }
            .disabled(status == .missingProjectFolder)
            Divider()
            Button("Reveal Project") {
                SkillStore.revealProjectInFinder(root)
            }
            Button("Reveal .claude/skills") {
                SkillStore.revealProjectSkillsFolderInFinder(root)
            }
            .disabled(status == .missingProjectFolder || status == .missingSkillsFolder)
            Divider()
            Button("Remove Project", role: .destructive) {
                skillStore.removeProjectSkillRoot(root)
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private func projectDetailView(_ root: ProjectSkillRoot) -> some View {
        let status = skillStore.projectSkillRootStatus(for: root)
        let skills = filteredProjectSkills(for: root)
        let agents = filteredProjectAgents(for: root)
        let allSkills = skillStore.projectSkills(for: root)
        let allAgents = skillStore.projectAgents(for: root)
        let instructions = skillStore.projectInstructions(for: root)
        let conflicts = skillStore.projectConflicts(for: root)
        let recents = recentItems(for: root)
        let trustStatus = skillStore.projectTrustStatus(for: root)

        return VStack(spacing: 0) {
            header(title: root.name, showsAddButton: false) {
                selectedProjectRootID = nil
                projectSearchText = ""
            }

            Divider()

            ScrollView {
                VStack(spacing: 10) {
                    projectSummaryCard(
                        root: root,
                        status: status,
                        skills: allSkills,
                        agents: allAgents,
                        instructions: instructions,
                        conflicts: conflicts,
                        recents: recents,
                        trustStatus: trustStatus
                    )

                    projectQuickActionsCard(root: root, status: status, skillCount: allSkills.count, trustStatus: trustStatus)

                    scopedSearchCard

                    if !conflicts.isEmpty {
                        projectConflictCenterCard(conflicts: conflicts)
                    }

                    projectInstructionsCard(root: root, instructions: instructions)

                    projectRecentsCard(items: recents)

                    projectItemsCard(title: "PROJECT SKILLS", count: skills.count) {
                        if skills.isEmpty {
                            projectEmptyText(projectSearchText.isEmpty ? "No project skills found." : "No project skills match this search.")
                        } else {
                            ForEach(Array(skills.enumerated()), id: \.element.id) { index, skill in
                                if index > 0 {
                                    sectionDivider
                                }
                                projectSkillResultRow(skill, root: root)
                            }
                        }
                    }

                    projectItemsCard(title: "PROJECT AGENTS", count: agents.count) {
                        if agents.isEmpty {
                            projectEmptyText(projectSearchText.isEmpty ? "No project agents found." : "No project agents match this search.")
                        } else {
                            ForEach(Array(agents.enumerated()), id: \.element.id) { index, agent in
                                if index > 0 {
                                    sectionDivider
                                }
                                projectAgentResultRow(agent)
                            }
                        }
                    }
                }
                .padding(14)
            }
        }
    }

    private func projectSummaryCard(
        root: ProjectSkillRoot,
        status: ProjectSkillRootStatus,
        skills: [Skill],
        agents: [Agent],
        instructions: [ProjectInstructionFile],
        conflicts: [ProjectSkillConflict],
        recents: [ProjectRecentItem],
        trustStatus: ProjectTrustStatus
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: projectRootIcon(for: status))
                    .font(.system(size: 18))
                    .foregroundStyle(projectRootTint(for: status))
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 6) {
                    Text(root.path)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(projectRootDetailText(for: root, status: status, skillCount: skills.count))
                        .font(.system(size: 12))
                        .foregroundStyle(status.isUnavailable ? projectRootTint(for: status) : .secondary)
                }
            }

            HStack(spacing: 8) {
                statPill(value: "\(skills.count)", label: "Skills")
                statPill(value: "\(agents.count)", label: "Agents")
                statPill(value: "\(instructions.count)", label: "Instructions")
                statPill(value: "\(conflicts.count)", label: "Conflicts")
            }

            HStack(spacing: 6) {
                ForEach(healthBadges(for: root, status: status, skillCount: skills.count, conflicts: conflicts, recentCount: recents.count, changedSinceScan: changedSinceLastScan(for: root), trustStatus: trustStatus), id: \.label) { badge in
                    projectRootBadge(badge.label, tint: badge.tint, secondary: badge.secondary)
                }
            }

            if let lastScanned = projectRootLastScannedText(for: root, status: status) {
                Text(lastScanned)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: cardRadius))
    }

    private func projectQuickActionsCard(
        root: ProjectSkillRoot,
        status: ProjectSkillRootStatus,
        skillCount: Int,
        trustStatus: ProjectTrustStatus
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("QUICK ACTIONS")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .tracking(0.5)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 8)], alignment: .leading, spacing: 8) {
                projectActionButton("Collection", icon: "square.stack.3d.up", tint: .blue) {
                    createCollection(from: root)
                }
                .disabled(skillCount == 0)

                projectActionButton("Claude Code", icon: "terminal", tint: .orange) {
                    SkillStore.openProjectInClaudeCode(root)
                }

                projectActionButton("Codex", icon: "apple.terminal", tint: .purple) {
                    SkillStore.openProjectInCodex(root)
                }

                projectActionButton(preferredEditor.shortTitle, icon: "chevron.left.forwardslash.chevron.right", tint: .secondary) {
                    SkillStore.openProject(root, in: preferredEditor)
                }

                if status == .missingSkillsFolder {
                    projectActionButton("Create Skills Folder", icon: "folder.badge.plus", tint: .orange) {
                        createProjectSkillsFolder(for: root)
                    }
                }

                if trustStatus.needsAction {
                    projectActionButton("Trust Changes", icon: "checkmark.shield", tint: .green) {
                        skillStore.trustCurrentProjectContent(for: root)
                        showActionMessage("Project files trusted")
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: cardRadius))
    }

    private var scopedSearchCard: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13))
                .foregroundStyle(.tertiary)
            TextField("Search this project's skills and agents", text: $projectSearchText)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
            if !projectSearchText.isEmpty {
                Button {
                    projectSearchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: cardRadius))
    }

    private func projectConflictCenterCard(conflicts: [ProjectSkillConflict]) -> some View {
        projectItemsCard(title: "CONFLICTS", count: conflicts.count, tint: .orange) {
            ForEach(Array(conflicts.enumerated()), id: \.element.id) { index, conflict in
                if index > 0 {
                    sectionDivider
                }
                projectConflictRow(conflict)
            }
        }
    }

    private func projectConflictRow(_ conflict: ProjectSkillConflict) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12))
                .foregroundStyle(.orange)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 4) {
                Text(conflict.skill.displayName)
                    .font(.system(size: 13, weight: .medium))
                Text(conflict.summary.helpText)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            Menu {
                Button("Reveal Project Version") {
                    SkillStore.revealInFinder(conflict.skill)
                }
                if let conflictingSkill = skillStore.firstConflictingSkill(for: conflict.skill) {
                    Button("Reveal Conflicting Skill") {
                        SkillStore.revealInFinder(conflictingSkill)
                    }
                }
                if let root = skillStore.projectSkillRoot(for: conflict.skill) {
                    Button("Disable Project Version") {
                        skillStore.setProjectSkillRoot(root, isEnabled: false)
                        selectedProjectRootID = nil
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
        }
        .padding(.vertical, 8)
    }

    private func projectInstructionsCard(root: ProjectSkillRoot, instructions: [ProjectInstructionFile]) -> some View {
        projectItemsCard(title: "PROJECT INSTRUCTIONS", count: instructions.count, tint: .purple) {
            if instructions.isEmpty {
                projectEmptyText("No CLAUDE.md, AGENTS.md, or .codex/AGENTS.md found.")
            } else {
                ForEach(Array(instructions.enumerated()), id: \.element.id) { index, instruction in
                    if index > 0 {
                        sectionDivider
                    }
                    HStack(spacing: 10) {
                        Image(systemName: instruction.kind == .claudeRoot ? "doc.text" : "doc.badge.gearshape")
                            .font(.system(size: 12))
                            .foregroundStyle(.purple)
                            .frame(width: 18)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(instruction.displayName)
                                .font(.system(size: 13, weight: .medium))
                            Text(instruction.sourceLabel)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(preferredEditor.openMenuTitle) {
                            SkillStore.open(URL(fileURLWithPath: instruction.path), in: preferredEditor)
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.blue)
                    }
                    .padding(.vertical, 8)
                }
            }
        }
    }

    private func projectRecentsCard(items: [ProjectRecentItem]) -> some View {
        projectItemsCard(title: "RECENTLY CHANGED IN THIS PROJECT", count: items.count, tint: .teal) {
            if items.isEmpty {
                projectEmptyText("No project skills, agents, or instructions changed in the last 7 days.")
            } else {
                ForEach(Array(items.prefix(8).enumerated()), id: \.element.id) { index, item in
                    if index > 0 {
                        sectionDivider
                    }
                    HStack(spacing: 10) {
                        Image(systemName: item.iconName)
                            .font(.system(size: 12))
                            .foregroundStyle(item.tint)
                            .frame(width: 18)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.title)
                                .font(.system(size: 13, weight: .medium))
                            Text("\(item.subtitle) changed \(relativeDate(item.date))")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 8)
                }
            }
        }
    }

    private func projectItemsCard<Content: View>(
        title: String,
        count: Int,
        tint: Color = .secondary,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .tracking(0.5)
                countBadge("\(count)", tint: tint)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 4)

            content()
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
        }
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: cardRadius))
    }

    private func projectSkillResultRow(_ skill: Skill, root: ProjectSkillRoot) -> some View {
        let isProjectPinned = skillStore.isProjectPinned(skill, in: root)

        return HStack(spacing: 10) {
            Image(skill.source.iconName)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 18, height: 18)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(skill.displayName)
                        .font(.system(size: 13, weight: .medium))
                    Text(skill.triggerCommand)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                if !skill.shortDescription.isEmpty {
                    Text(skill.shortDescription)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer()

            Button {
                skillStore.toggleProjectPin(skill, in: root)
            } label: {
                Image(systemName: isProjectPinned ? "pin.fill" : "pin")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(isProjectPinned ? .blue : .secondary)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(isProjectPinned ? "Unpin in this project" : "Pin in this project")

            Button(preferredEditor.openMenuTitle) {
                SkillStore.openSkill(skill, in: preferredEditor)
            }
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.blue)
        }
        .padding(.vertical, 8)
    }

    private func projectAgentResultRow(_ agent: Agent) -> some View {
        HStack(spacing: 10) {
            Image("ClaudeLogo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 18, height: 18)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(agent.displayName)
                        .font(.system(size: 13, weight: .medium))
                    Text(agent.identifier)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                if !agent.shortDescription.isEmpty {
                    Text(agent.shortDescription)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer()

            Button(preferredEditor.openMenuTitle) {
                SkillStore.openAgent(agent, in: preferredEditor)
            }
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.blue)
        }
        .padding(.vertical, 8)
    }

    private func projectRootPreview(root: ProjectSkillRoot, skillCount: Int) -> some View {
        let instructionCount = ProjectInstructionKind.allCases.filter { kind in
            fileManager.fileExists(atPath: (root.path as NSString).appendingPathComponent(kind.relativePath))
        }.count
        let agentCount = AgentScanner().scanProjectAgents(in: root).count
        let missingSkillsFolder = !fileManager.fileExists(atPath: root.claudeSkillsPath)

        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: missingSkillsFolder ? "folder.badge.questionmark" : "checkmark.shield")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(missingSkillsFolder ? .orange : .blue)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Add \(root.name)?")
                        .font(.system(size: 13, weight: .semibold))
                    Text("\(projectSkillCountLabel(skillCount)), \(projectAgentCountLabel(agentCount)), and \(instructionCount) instruction files found.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Text("SkillsBar will watch approved project instruction, skill, and agent paths. It will not scan the rest of the repo for skills.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 8) {
                Button("Add Project") {
                    skillStore.addProjectSkillRoot(root)
                    pendingProjectRoot = nil
                    pendingProjectSkillCount = nil
                    showActionMessage("Project added")
                }
                .keyboardShortcut(.defaultAction)

                if missingSkillsFolder {
                    Button("Create .claude/skills Folder") {
                        createProjectSkillsFolder(for: root)
                        pendingProjectSkillCount = 0
                    }
                }

                Button("Open Project") {
                    SkillStore.openProject(root, in: preferredEditor)
                }

                Button("Cancel") {
                    pendingProjectRoot = nil
                    pendingProjectSkillCount = nil
                }
            }
        }
        .padding(10)
        .background(Color.blue.opacity(0.08))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.blue.opacity(0.12), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func chooseProjectRoot() {
        NSApp.activate(ignoringOtherApps: true)

        let panel = NSOpenPanel()
        panel.title = "Add Project Skills"
        panel.message = "Choose a project folder. SkillsBar will only read trusted project instruction, skill, and agent paths inside it."
        panel.prompt = "Choose Project"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let url = panel.url else { return }

        let root = ProjectSkillRoot(path: url.path)
        pendingProjectRoot = root
        pendingProjectSkillCount = SkillScanner().scanClaudeCodeProjectSkills(in: root).count
    }

    private func createCollection(from root: ProjectSkillRoot) {
        let collection = skillStore.createCollectionFromProject(root)
        showActionMessage("Created \(collection.name)")
    }

    private func createProjectSkillsFolder(for root: ProjectSkillRoot) {
        if skillStore.createProjectSkillsFolder(for: root) {
            showActionMessage("Created .claude/skills")
        } else {
            showActionMessage("Could not create folder")
        }
    }

    private func commitProjectRename(_ root: ProjectSkillRoot) {
        skillStore.renameProjectSkillRoot(root, to: editingProjectName)
        editingProjectRootID = nil
        editingProjectName = ""
    }

    private func filteredProjectSkills(for root: ProjectSkillRoot) -> [Skill] {
        let skills = skillStore.projectSkills(for: root)
        let query = projectSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return skillStore.projectSortedSkills(for: root, skills: skills) }

        let filtered = skills.filter { skill in
            [
                skill.displayName,
                skill.description,
                skill.triggerCommand,
                skill.path,
            ].contains { $0.lowercased().contains(query) }
        }
        return skillStore.projectSortedSkills(for: root, skills: filtered)
    }

    private func filteredProjectAgents(for root: ProjectSkillRoot) -> [Agent] {
        let agents = skillStore.projectAgents(for: root)
        let query = projectSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return agents }
        return agents.filter { agent in
            [
                agent.displayName,
                agent.description,
                agent.identifier,
                agent.path,
            ].contains { $0.lowercased().contains(query) }
        }
    }

    private var allProjectConflicts: [ProjectSkillConflict] {
        skillStore.orderedProjectSkillRoots.flatMap { skillStore.projectConflicts(for: $0) }
    }

    private var pinnedProjectRoots: [ProjectSkillRoot] {
        skillStore.orderedProjectSkillRoots.filter(\.isPinned)
    }

    private func recentItems(for root: ProjectSkillRoot) -> [ProjectRecentItem] {
        let skillItems = skillStore.projectSkills(for: root).compactMap { skill -> ProjectRecentItem? in
            guard let date = skill.lastModified, Date().timeIntervalSince(date) <= projectRecentWindow else { return nil }
            return ProjectRecentItem(title: skill.displayName, subtitle: "Skill", date: date, iconName: "sparkles", tint: .blue)
        }

        let agentItems = skillStore.projectAgents(for: root).compactMap { agent -> ProjectRecentItem? in
            guard let date = agent.lastModified, Date().timeIntervalSince(date) <= projectRecentWindow else { return nil }
            return ProjectRecentItem(title: agent.displayName, subtitle: "Agent", date: date, iconName: "person.crop.circle.badge.gearshape", tint: .cyan)
        }

        let instructionItems = skillStore.projectInstructions(for: root).compactMap { instruction -> ProjectRecentItem? in
            guard let date = instruction.lastModified, Date().timeIntervalSince(date) <= projectRecentWindow else { return nil }
            return ProjectRecentItem(title: instruction.displayName, subtitle: instruction.sourceLabel, date: date, iconName: "doc.text", tint: .purple)
        }

        return (skillItems + agentItems + instructionItems).sorted { lhs, rhs in
            if lhs.date != rhs.date { return lhs.date > rhs.date }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }

    private func healthBadges(
        for root: ProjectSkillRoot,
        status: ProjectSkillRootStatus,
        skillCount: Int,
        conflicts: [ProjectSkillConflict],
        recentCount: Int,
        changedSinceScan: Bool,
        trustStatus: ProjectTrustStatus
    ) -> [ProjectHealthBadge] {
        var badges: [ProjectHealthBadge] = []

        switch status {
        case .disabled:
            badges.append(ProjectHealthBadge(label: "disabled", tint: .secondary, secondary: true))
        case .available:
            if skillCount == 0 {
                badges.append(ProjectHealthBadge(label: "zero skills", tint: .orange, secondary: true))
            }
        case .missingSkillsFolder:
            badges.append(ProjectHealthBadge(label: "missing skills folder", tint: .orange, secondary: true))
        case .missingProjectFolder:
            badges.append(ProjectHealthBadge(label: "inaccessible path", tint: .red, secondary: true))
        }

        if !conflicts.isEmpty {
            badges.append(ProjectHealthBadge(label: "\(conflicts.count) conflicts", tint: .orange, secondary: true))
        }

        if recentCount > 0 {
            badges.append(ProjectHealthBadge(label: "\(recentCount) recent", tint: .teal, secondary: true))
        }

        if changedSinceScan {
            badges.append(ProjectHealthBadge(label: "changed since scan", tint: .indigo, secondary: true))
        }

        if trustStatus.needsAction {
            badges.append(ProjectHealthBadge(label: "review files", tint: .green, secondary: true))
        }

        if badges.isEmpty {
            badges.append(ProjectHealthBadge(label: "healthy", tint: .green, secondary: true))
        }

        return badges
    }

    private func changedSinceLastScan(for root: ProjectSkillRoot) -> Bool {
        guard let lastRefreshDate = skillStore.lastRefreshDate else { return false }

        let skillChanged = skillStore.projectSkills(for: root).contains { skill in
            guard let lastModified = skill.lastModified else { return false }
            return lastModified > lastRefreshDate
        }

        let agentChanged = skillStore.projectAgents(for: root).contains { agent in
            guard let lastModified = agent.lastModified else { return false }
            return lastModified > lastRefreshDate
        }

        let instructionChanged = skillStore.projectInstructions(for: root).contains { instruction in
            guard let lastModified = instruction.lastModified else { return false }
            return lastModified > lastRefreshDate
        }

        return skillChanged || agentChanged || instructionChanged
    }

    private func projectSkillCountLabel(_ count: Int) -> String {
        count == 1 ? "1 skill" : "\(count) skills"
    }

    private func projectAgentCountLabel(_ count: Int) -> String {
        count == 1 ? "1 agent" : "\(count) agents"
    }

    private func projectRootIcon(for status: ProjectSkillRootStatus) -> String {
        switch status {
        case .disabled:
            return "folder"
        case .available:
            return "folder.badge.gearshape"
        case .missingSkillsFolder:
            return "folder.badge.questionmark"
        case .missingProjectFolder:
            return "externaldrive.badge.exclamationmark"
        }
    }

    private func projectRootTint(for status: ProjectSkillRootStatus) -> Color {
        switch status {
        case .disabled:
            return .secondary
        case .available:
            return .blue
        case .missingSkillsFolder:
            return .orange
        case .missingProjectFolder:
            return .red.opacity(0.85)
        }
    }

    private func projectRootBadge(_ text: String, tint: Color, secondary: Bool = false) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(tint)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(tint.opacity(secondary ? 0.08 : 0.14))
            .clipShape(Capsule())
    }

    private func countBadge(_ text: String, tint: Color = .secondary) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(tint)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(tint.opacity(0.12))
            .clipShape(Capsule())
    }

    private func statPill(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .monospaced))
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 9)
        .background(Color.primary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func projectActionButton(_ title: String, icon: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(tint.opacity(0.10))
            .foregroundStyle(tint)
            .clipShape(RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
    }

    private func projectEmptyText(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 10)
    }

    private func projectRootDetailText(for root: ProjectSkillRoot, status: ProjectSkillRootStatus, skillCount: Int) -> String {
        switch status {
        case .disabled:
            return "Paused. Enable it to scan this project."
        case .available:
            return "\(projectSkillCountLabel(skillCount)) from .claude/skills"
        case .missingSkillsFolder:
            return "Project exists, but .claude/skills is missing."
        case .missingProjectFolder:
            return "Project folder is unavailable."
        }
    }

    private func projectRootLastScannedText(for root: ProjectSkillRoot, status: ProjectSkillRootStatus) -> String? {
        guard root.isEnabled, status != .missingProjectFolder, let lastRefreshDate = skillStore.lastRefreshDate else {
            return nil
        }

        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return "Scanned \(formatter.localizedString(for: lastRefreshDate, relativeTo: Date()))"
    }

    private func abbreviatedPath(_ path: String) -> String {
        let homePath = fileManager.homeDirectoryForCurrentUser.path
        if path == homePath {
            return "~"
        }
        if path.hasPrefix(homePath + "/") {
            return "~" + path.dropFirst(homePath.count)
        }
        return path
    }

    private func relativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func showActionMessage(_ message: String) {
        actionDismissWorkItem?.cancel()
        withAnimation(.easeInOut(duration: 0.18)) {
            actionMessage = message
        }

        let workItem = DispatchWorkItem {
            withAnimation(.easeInOut(duration: 0.18)) {
                actionMessage = nil
            }
            actionDismissWorkItem = nil
        }

        actionDismissWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: workItem)
    }

    private var preferredEditor: ExternalEditor {
        ExternalEditor.resolved(for: preferredEditorRaw)
    }

    private var sectionDivider: some View {
        Divider()
            .overlay(Color.primary.opacity(0.05))
            .padding(.leading, 40)
    }
}

private struct ProjectHealthBadge {
    let label: String
    let tint: Color
    let secondary: Bool
}

private struct ProjectRecentItem: Identifiable {
    let title: String
    let subtitle: String
    let date: Date
    let iconName: String
    let tint: Color

    var id: String {
        "\(subtitle)-\(title)-\(date.timeIntervalSince1970)"
    }
}

private struct ProjectRootDropDelegate: DropDelegate {
    let targetRoot: ProjectSkillRoot
    let skillStore: SkillStore
    @Binding var draggingProjectRootID: UUID?

    func dropEntered(info: DropInfo) {
        guard let draggingProjectRootID,
              draggingProjectRootID != targetRoot.id else {
            return
        }

        skillStore.moveProjectSkillRoot(from: draggingProjectRootID, before: targetRoot.id)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggingProjectRootID = nil
        return true
    }
}
