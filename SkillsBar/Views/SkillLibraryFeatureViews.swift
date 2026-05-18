import SwiftUI
import UniformTypeIdentifiers

private let featureCardBackground = Color.primary.opacity(0.10)
private let featureCardRadius: CGFloat = 12
private let featureRecentWindow: TimeInterval = 7 * 24 * 60 * 60

struct CommandPaletteView: View {
    @ObservedObject var store: SkillStore
    @ObservedObject var usageTracker: UsageTracker
    let onBack: () -> Void
    let onSelectSkill: (Skill) -> Void
    let onSelectAgent: (Agent) -> Void
    let onSelectPlugin: (Plugin) -> Void
    let onSelectCollection: (SkillCollection) -> Void
    let onSelectProject: (ProjectSkillRoot) -> Void
    let onOpenScreen: (SkillsBarToolScreen) -> Void
    let onCopyTrigger: (Skill) -> Void
    let onOpenSkillInEditor: (Skill) -> Void
    let onRefresh: () -> Void

    @State private var query = ""
    @FocusState private var focused: Bool

    private enum PaletteItem: Identifiable {
        case screen(SkillsBarToolScreen)
        case skill(Skill)
        case agent(Agent)
        case plugin(Plugin)
        case collection(SkillCollection)
        case project(ProjectSkillRoot)
        case action(id: String, title: String, detail: String, iconName: String, action: () -> Void)

        var id: String {
            switch self {
            case .screen(let screen):
                return "screen-\(screen.rawValue)"
            case .skill(let skill):
                return "skill-\(skill.id)"
            case .agent(let agent):
                return "agent-\(agent.id)"
            case .plugin(let plugin):
                return "plugin-\(plugin.id)"
            case .collection(let collection):
                return "collection-\(collection.id.uuidString)"
            case .project(let project):
                return "project-\(project.id.uuidString)"
            case .action(let id, _, _, _, _):
                return "action-\(id)"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            featureHeader(title: "Command Palette", subtitle: "Search everything", onBack: onBack)

            Divider()

            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "command")
                        .foregroundStyle(.secondary)
                    TextField("Search skills, agents, plugins, projects, tools, actions", text: $query)
                        .textFieldStyle(.plain)
                        .focused($focused)
                        .onSubmit(openFirstItem)
                    if !query.isEmpty {
                        Button {
                            query = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(11)
                .background(featureCardBackground)
                .clipShape(RoundedRectangle(cornerRadius: featureCardRadius))

                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(filteredItems) { item in
                            paletteRow(item)
                        }
                    }
                }
                .frame(maxHeight: SkillsBarLayout.mainScrollHeight)
            }
            .padding(14)
        }
        .frame(width: SkillsBarLayout.windowWidth, height: SkillsBarLayout.detailHeight)
        .onAppear {
            DispatchQueue.main.async { focused = true }
        }
    }

    private var filteredItems: [PaletteItem] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let items = allItems
        guard !normalizedQuery.isEmpty else { return Array(items.prefix(80)) }
        return items.filter { item in
            paletteSearchText(for: item).contains(normalizedQuery)
        }
        .prefix(80)
        .map { $0 }
    }

    private var allItems: [PaletteItem] {
        let screens: [PaletteItem] = SkillsBarToolScreen.allCases
            .filter { $0 != .commandPalette }
            .map { .screen($0) }

        let actions: [PaletteItem] = [
            .action(id: "refresh", title: "Refresh all", detail: "Rescan skills, agents, plugins, and usage", iconName: "arrow.clockwise", action: onRefresh),
        ]

        return screens +
            actions +
            store.allSkills.map { .skill($0) } +
            store.allAgents.map { .agent($0) } +
            store.plugins.map { .plugin($0) } +
            store.orderedCollections.map { .collection($0) } +
            store.orderedProjectSkillRoots.map { .project($0) }
    }

    @ViewBuilder
    private func paletteRow(_ item: PaletteItem) -> some View {
        switch item {
        case .screen(let screen):
            commandRow(
                iconName: screen.iconName,
                title: screen.title,
                detail: "Open tool",
                badge: "Tool",
                action: { onOpenScreen(screen) }
            )
        case .skill(let skill):
            commandRow(
                iconName: skill.source.iconName,
                title: skill.displayName,
                detail: "\(skill.triggerCommand) - \(skill.source.shortScopeLabel)",
                badge: "Skill",
                action: { onSelectSkill(skill) },
                trailing: {
                    compactRowButton("Copy", systemImage: "doc.on.doc") { onCopyTrigger(skill) }
                    compactRowButton("Open", systemImage: "chevron.left.forwardslash.chevron.right") { onOpenSkillInEditor(skill) }
                }
            )
        case .agent(let agent):
            commandRow(
                iconName: "person.crop.circle",
                title: agent.displayName,
                detail: "\(agent.identifier) - \(agent.source.sectionTitle)",
                badge: "Agent",
                action: { onSelectAgent(agent) }
            )
        case .plugin(let plugin):
            commandRow(
                iconName: "shippingbox",
                title: plugin.displayName,
                detail: plugin.version.map { "v\($0)" } ?? plugin.shortDescription,
                badge: "Plugin",
                action: { onSelectPlugin(plugin) }
            )
        case .collection(let collection):
            commandRow(
                iconName: collection.iconName,
                title: collection.name,
                detail: "\(collection.skillPaths.count) saved paths",
                badge: "Collection",
                action: { onSelectCollection(collection) }
            )
        case .project(let project):
            commandRow(
                iconName: project.isPinned ? "pin.fill" : "folder",
                title: project.name,
                detail: project.path,
                badge: "Project",
                action: { onSelectProject(project) }
            )
        case .action(_, let title, let detail, let iconName, let action):
            commandRow(
                iconName: iconName,
                title: title,
                detail: detail,
                badge: "Action",
                action: action
            )
        }
    }

    private func commandRow<Trailing: View>(
        iconName: String,
        title: String,
        detail: String,
        badge: String,
        action: @escaping () -> Void,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                paletteIcon(iconName)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(title)
                            .font(.system(size: 13, weight: .medium))
                            .lineLimit(1)
                        Text(badge)
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.12))
                            .foregroundStyle(.secondary)
                            .clipShape(Capsule())
                    }
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()
                trailing()
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(featureCardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    private func commandRow(
        iconName: String,
        title: String,
        detail: String,
        badge: String,
        action: @escaping () -> Void
    ) -> some View {
        commandRow(iconName: iconName, title: title, detail: detail, badge: badge, action: action) {
            Image(systemName: "return")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
    }

    private func compactRowButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 22, height: 22)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help(title)
    }

    @ViewBuilder
    private func paletteIcon(_ iconName: String) -> some View {
        if iconName == "ClaudeLogo" || iconName == "CodexLogo" {
            Image(iconName)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 18, height: 18)
        } else {
            Image(systemName: iconName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 18, height: 18)
        }
    }

    private func paletteSearchText(for item: PaletteItem) -> String {
        switch item {
        case .screen(let screen):
            return "\(screen.title) \(screen.rawValue) tool".lowercased()
        case .skill(let skill):
            return "\(skill.displayName) \(skill.description) \(skill.triggerCommand) \(skill.path) \(skill.source.shortScopeLabel)".lowercased()
        case .agent(let agent):
            return "\(agent.displayName) \(agent.description) \(agent.identifier) \(agent.path) \(agent.source.sectionTitle)".lowercased()
        case .plugin(let plugin):
            return "\(plugin.displayName) \(plugin.shortDescription) \(plugin.version ?? "") \(plugin.path)".lowercased()
        case .collection(let collection):
            return "\(collection.name) collection".lowercased()
        case .project(let project):
            return "\(project.name) \(project.path) project".lowercased()
        case .action(_, let title, let detail, _, _):
            return "\(title) \(detail) action".lowercased()
        }
    }

    private func openFirstItem() {
        guard let first = filteredItems.first else { return }
        switch first {
        case .screen(let screen):
            onOpenScreen(screen)
        case .skill(let skill):
            onSelectSkill(skill)
        case .agent(let agent):
            onSelectAgent(agent)
        case .plugin(let plugin):
            onSelectPlugin(plugin)
        case .collection(let collection):
            onSelectCollection(collection)
        case .project(let project):
            onSelectProject(project)
        case .action(_, _, _, _, let action):
            action()
        }
    }
}

struct SkillHealthView: View {
    @ObservedObject var store: SkillStore
    @ObservedObject var usageTracker: UsageTracker
    let onBack: () -> Void
    let onSelectSkillPath: (String) -> Void
    let onRefresh: () -> Void
    let onToast: (String) -> Void

    private var issues: [SkillHealthIssue] {
        store.skillHealthIssues(usageTracker: usageTracker)
    }

    var body: some View {
        VStack(spacing: 0) {
            featureHeader(title: "Skill Health", subtitle: "\(issues.count) checks need attention", onBack: onBack)
            Divider()
            ScrollView {
                VStack(spacing: 10) {
                    healthSummaryCard
                    healthActionsCard
                    if issues.isEmpty {
                        emptyFeatureState(icon: "checkmark.seal", title: "Everything looks healthy", detail: "No invalid frontmatter, missing descriptions, duplicate triggers, missing collection paths, unreadable folders, or stale pins were found.")
                    } else {
                        ForEach(SkillHealthCategory.allCases) { category in
                            let categoryIssues = issues.filter { $0.category == category }
                            if !categoryIssues.isEmpty {
                                healthCategoryCard(category, issues: categoryIssues)
                            }
                        }
                    }
                }
                .padding(14)
            }
        }
        .frame(width: SkillsBarLayout.windowWidth, height: SkillsBarLayout.detailHeight)
    }

    private var healthSummaryCard: some View {
        HStack(spacing: 8) {
            healthMetric("Critical", issues.filter { $0.severity == .critical }.count, color: .red)
            healthMetric("Warnings", issues.filter { $0.severity == .warning }.count, color: .orange)
            healthMetric("Info", issues.filter { $0.severity == .info }.count, color: .blue)
        }
        .padding(12)
        .background(featureCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: featureCardRadius))
    }

    private var healthActionsCard: some View {
        HStack(spacing: 10) {
            Button("Refresh") {
                onRefresh()
            }
            Button("Clean Stale Pins") {
                let count = store.clearStalePinnedItems()
                onToast(count == 1 ? "Cleared 1 stale pin" : "Cleared \(count) stale pins")
            }
            Button("Clear Missing Collection Paths") {
                let count = store.clearAllMissingCollectionPaths()
                onToast(count == 1 ? "Cleared 1 missing path" : "Cleared \(count) missing paths")
            }
        }
        .font(.system(size: 12, weight: .medium))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(featureCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: featureCardRadius))
    }

    private func healthMetric(_ title: String, _ count: Int, color: Color) -> some View {
        VStack(spacing: 4) {
            Text("\(count)")
                .font(.system(size: 18, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(color.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func healthCategoryCard(_ category: SkillHealthCategory, issues: [SkillHealthIssue]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle(category.title, count: issues.count)
            ForEach(issues) { issue in
                Divider()
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: severityIcon(issue.severity))
                        .foregroundStyle(severityColor(issue.severity))
                        .frame(width: 18)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(issue.title)
                            .font(.system(size: 13, weight: .medium))
                        Text(issue.detail)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    if let skillPath = issue.skillPath {
                        Button("Open") {
                            onSelectSkillPath(skillPath)
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.blue)
                    } else if let path = issue.path {
                        Button("Reveal") {
                            NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "")
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.blue)
                    }
                }
            }
        }
        .padding(12)
        .background(featureCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: featureCardRadius))
    }
}

struct SmartCollectionsView: View {
    @ObservedObject var store: SkillStore
    @ObservedObject var usageTracker: UsageTracker
    let onBack: () -> Void
    let onSelectSkill: (Skill) -> Void
    let onToast: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            featureHeader(title: "Smart Collections", subtitle: "Dynamic groups you can save as copies", onBack: onBack)
            Divider()
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(SmartCollectionKind.allCases) { kind in
                        smartCollectionCard(store.smartCollection(for: kind, usageTracker: usageTracker))
                    }
                }
                .padding(14)
            }
        }
        .frame(width: SkillsBarLayout.windowWidth, height: SkillsBarLayout.detailHeight)
    }

    private func smartCollectionCard(_ resolved: ResolvedSmartCollection) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: resolved.kind.iconName)
                    .foregroundStyle(.blue)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text(resolved.kind.title)
                        .font(.system(size: 13, weight: .semibold))
                    Text(resolved.kind.detail)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                countPill("\(resolved.skills.count)")
                Button("Save Copy") {
                    let collection = store.saveSmartCollectionCopy(resolved.kind, usageTracker: usageTracker)
                    onToast("Saved \(collection.name)")
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.blue)
            }

            if resolved.skills.isEmpty {
                Text("No matching skills right now.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(resolved.skills.prefix(6)), id: \.id) { skill in
                    Button {
                        onSelectSkill(skill)
                    } label: {
                        HStack(spacing: 8) {
                            Text(skill.displayName)
                                .font(.system(size: 12, weight: .medium))
                            Spacer()
                            Text(skill.triggerCommand)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
                if resolved.skills.count > 6 {
                    Text("+ \(resolved.skills.count - 6) more")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(12)
        .background(featureCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: featureCardRadius))
    }
}

struct ConflictCenterView: View {
    @ObservedObject var store: SkillStore
    let onBack: () -> Void
    let onSelectSkill: (Skill) -> Void
    let onCopyTrigger: (Skill) -> Void

    private var groups: [SkillConflictGroup] {
        store.conflictGroups()
    }

    var body: some View {
        VStack(spacing: 0) {
            featureHeader(title: "Conflict Center", subtitle: "\(groups.count) duplicate names or triggers", onBack: onBack)
            Divider()
            ScrollView {
                VStack(spacing: 10) {
                    if groups.isEmpty {
                        emptyFeatureState(icon: "checkmark.seal", title: "No conflicts found", detail: "No duplicate names or triggers across user, plugin, built-in, and project skills.")
                    } else {
                        ForEach(groups) { group in
                            conflictGroupCard(group)
                        }
                    }
                }
                .padding(14)
            }
        }
        .frame(width: SkillsBarLayout.windowWidth, height: SkillsBarLayout.detailHeight)
    }

    private func conflictGroupCard(_ group: SkillConflictGroup) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle(group.title.uppercased(), count: group.skills.count)
            ForEach(group.skills, id: \.id) { skill in
                Divider()
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(skill.displayName)
                            .font(.system(size: 13, weight: .medium))
                        Text("\(skill.triggerCommand) - \(skill.source.shortScopeLabel)")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Open") {
                        onSelectSkill(skill)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.blue)
                    Button("Copy") {
                        onCopyTrigger(skill)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .background(featureCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: featureCardRadius))
    }
}

struct InstructionsHubView: View {
    @ObservedObject var store: SkillStore
    let preferredEditor: ExternalEditor
    let onBack: () -> Void

    private var items: [InstructionHubItem] {
        store.instructionHubItems()
    }

    var body: some View {
        VStack(spacing: 0) {
            featureHeader(title: "Instructions Hub", subtitle: "Global and project instruction files", onBack: onBack)
            Divider()
            ScrollView {
                VStack(spacing: 10) {
                    instructionSection("GLOBAL", items: items.filter { $0.scope == .global })
                    instructionSection("PROJECTS", items: items.filter { $0.scope == .project })
                }
                .padding(14)
            }
        }
        .frame(width: SkillsBarLayout.windowWidth, height: SkillsBarLayout.detailHeight)
    }

    private func instructionSection(_ title: String, items: [InstructionHubItem]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle(title, count: items.count)
            ForEach(items) { item in
                Divider()
                HStack(spacing: 8) {
                    Image(systemName: item.exists ? "doc.text" : "doc.badge.plus")
                        .foregroundStyle(instructionTint(item))
                        .frame(width: 18)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(instructionTitle(item))
                            .font(.system(size: 13, weight: .medium))
                        Text(item.path)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    countPill(item.healthTitle)
                    Button(item.exists ? "Open" : "Create") {
                        SkillStore.open(URL(fileURLWithPath: item.path), in: preferredEditor)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.blue)
                }
            }
        }
        .padding(12)
        .background(featureCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: featureCardRadius))
    }

    private func instructionTitle(_ item: InstructionHubItem) -> String {
        if let projectName = item.projectName {
            return "\(projectName): \(item.displayName)"
        }
        return item.displayName
    }

    private func instructionTint(_ item: InstructionHubItem) -> Color {
        if !item.exists || !item.isReadable { return .orange }
        if item.isEmpty { return .yellow }
        return .blue
    }
}

struct ImportExportView: View {
    @ObservedObject var store: SkillStore
    let onBack: () -> Void
    let onToast: (String) -> Void

    @State private var preview: SkillLibraryImportPreview?
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            featureHeader(title: "Import and Export", subtitle: "Collections, pins, projects, and preferences", onBack: onBack)
            Divider()
            VStack(alignment: .leading, spacing: 12) {
                exportCard
                importCard
                if let preview {
                    previewCard(preview)
                }
                if let errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 12))
                        .foregroundStyle(.red)
                }
                Spacer()
            }
            .padding(14)
        }
        .frame(width: SkillsBarLayout.windowWidth, height: SkillsBarLayout.detailHeight)
    }

    private var exportCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("EXPORT", count: nil)
            Text("Exports collections, pinned order, trusted project list, project pins, and app preferences.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Button("Export Snapshot...") {
                exportSnapshot()
            }
        }
        .padding(14)
        .background(featureCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: featureCardRadius))
    }

    private var importCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("IMPORT", count: nil)
            Text("Choose a SkillsBar JSON export. You will see a preview before anything is applied.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Button("Choose Export...") {
                chooseImport()
            }
        }
        .padding(14)
        .background(featureCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: featureCardRadius))
    }

    private func previewCard(_ preview: SkillLibraryImportPreview) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("IMPORT PREVIEW", count: nil)
            HStack(spacing: 8) {
                previewMetric("Collections", preview.collectionCount)
                previewMetric("Pins", preview.pinnedCount)
                previewMetric("Projects", preview.projectCount)
                previewMetric("Project Pins", preview.projectPinnedCount)
            }
            Text("Applying replaces the matching local SkillsBar state with this snapshot.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Button("Apply Import") {
                store.applyImport(preview)
                self.preview = nil
                onToast("Imported snapshot")
            }
            .keyboardShortcut(.defaultAction)
        }
        .padding(14)
        .background(featureCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: featureCardRadius))
    }

    private func previewMetric(_ title: String, _ count: Int) -> some View {
        VStack(spacing: 4) {
            Text("\(count)")
                .font(.system(size: 16, weight: .bold, design: .monospaced))
            Text(title)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func exportSnapshot() {
        let panel = NSSavePanel()
        panel.title = "Export SkillsBar Snapshot"
        panel.nameFieldStringValue = "skillsbar-export.json"
        panel.allowedContentTypes = [.json]

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(store.exportSnapshot())
            try data.write(to: url, options: .atomic)
            onToast("Exported snapshot")
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func chooseImport() {
        let panel = NSOpenPanel()
        panel.title = "Import SkillsBar Snapshot"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.json]

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let data = try Data(contentsOf: url)
            preview = try store.importPreview(from: data)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            preview = nil
        }
    }
}

struct PluginAwarenessView: View {
    @ObservedObject var store: SkillStore
    let preferredEditor: ExternalEditor
    let onBack: () -> Void
    let onSelectPlugin: (Plugin) -> Void

    private var items: [PluginAwarenessItem] {
        store.pluginAwarenessItems()
    }

    var body: some View {
        VStack(spacing: 0) {
            featureHeader(title: "Plugin Updates", subtitle: "\(items.count) installed plugins", onBack: onBack)
            Divider()
            ScrollView {
                VStack(spacing: 10) {
                    if items.isEmpty {
                        emptyFeatureState(icon: "shippingbox", title: "No plugins found", detail: "Installed Codex plugins will appear here with version and recent change status.")
                    } else {
                        ForEach(items) { item in
                            pluginAwarenessCard(item)
                        }
                    }
                }
                .padding(14)
            }
        }
        .frame(width: SkillsBarLayout.windowWidth, height: SkillsBarLayout.detailHeight)
    }

    private func pluginAwarenessCard(_ item: PluginAwarenessItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "shippingbox")
                    .foregroundStyle(item.changedRecently ? .blue : .secondary)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.plugin.displayName)
                        .font(.system(size: 13, weight: .semibold))
                    Text(item.plugin.path)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                if let version = item.plugin.version {
                    countPill("v\(version)")
                }
                if item.changedRecently {
                    countPill("changed")
                }
                countPill("\(item.skillCount) skills")
            }

            HStack {
                Button("Open Detail") {
                    onSelectPlugin(item.plugin)
                }
                Button(preferredEditor.openMenuTitle) {
                    SkillStore.openPlugin(item.plugin, in: preferredEditor)
                }
                Button("Reveal") {
                    SkillStore.revealPluginInFinder(item.plugin)
                }
            }
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.blue)

            Text("Outdated detection will appear here when plugin metadata exposes a remote version source.")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .background(featureCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: featureCardRadius))
    }
}

private func featureHeader(title: String, subtitle: String, onBack: @escaping () -> Void) -> some View {
    HStack {
        Button(action: onBack) {
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

        VStack(spacing: 1) {
            Text(title)
                .font(.system(size: 16, weight: .bold))
            Text(subtitle)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }

        Spacer()

        Color.clear.frame(width: 52, height: 1)
    }
    .padding(.horizontal, 20)
    .padding(.vertical, 12)
}

private func sectionTitle(_ title: String, count: Int?) -> some View {
    HStack(spacing: 6) {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .tracking(0.5)
        if let count {
            countPill("\(count)")
        }
        Spacer()
    }
}

private func countPill(_ text: String) -> some View {
    Text(text)
        .font(.system(size: 10, weight: .medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color.secondary.opacity(0.12))
        .clipShape(Capsule())
}

private func emptyFeatureState(icon: String, title: String, detail: String) -> some View {
    VStack(spacing: 10) {
        Image(systemName: icon)
            .font(.system(size: 30))
            .foregroundStyle(.secondary)
        Text(title)
            .font(.system(size: 15, weight: .semibold))
        Text(detail)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 18)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 36)
    .background(featureCardBackground)
    .clipShape(RoundedRectangle(cornerRadius: featureCardRadius))
}

private func severityIcon(_ severity: SkillHealthSeverity) -> String {
    switch severity {
    case .critical:
        return "xmark.octagon.fill"
    case .warning:
        return "exclamationmark.triangle.fill"
    case .info:
        return "info.circle.fill"
    }
}

private func severityColor(_ severity: SkillHealthSeverity) -> Color {
    switch severity {
    case .critical:
        return .red
    case .warning:
        return .orange
    case .info:
        return .blue
    }
}
