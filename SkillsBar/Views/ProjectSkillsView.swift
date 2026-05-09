import AppKit
import SwiftUI

struct ProjectSkillsView: View {
    @ObservedObject var skillStore: SkillStore
    let onBack: () -> Void

    @AppStorage(AppPreferenceKey.preferredEditor) private var preferredEditorRaw = ExternalEditor.visualStudioCode.rawValue
    @State private var pendingProjectRoot: ProjectSkillRoot?
    @State private var pendingProjectSkillCount: Int?

    private let cardRadius: CGFloat = 12
    private let cardBackground = Color.primary.opacity(0.10)
    private let fileManager = FileManager.default

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            ScrollView {
                VStack(spacing: 10) {
                    projectListCard

                    if let pendingProjectRoot, let pendingProjectSkillCount {
                        projectRootPreview(root: pendingProjectRoot, skillCount: pendingProjectSkillCount)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .top)
            }
        }
        .frame(width: SkillsBarLayout.windowWidth, height: SkillsBarLayout.aboutHeight)
    }

    private var header: some View {
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

            Text("Project Skills")
                .font(.system(size: 16, weight: .semibold))

            Spacer()

            Button(action: chooseProjectRoot) {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 44, height: 20, alignment: .trailing)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.blue)
            .help("Add Project")
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
                ForEach(Array(skillStore.projectSkillRoots.enumerated()), id: \.element.id) { index, root in
                    if index > 0 {
                        sectionDivider
                    }
                    projectRootRow(root)
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

        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: projectRootIcon(for: status))
                .font(.system(size: 12))
                .foregroundStyle(projectRootTint(for: status))
                .frame(width: 18, height: 18)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(root.name)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.primary)
                    projectRootBadge(status.title, tint: projectRootTint(for: status))
                    if status == .available {
                        projectRootBadge(projectSkillCountLabel(skillCount), tint: .secondary, secondary: true)
                    }
                }

                Text(abbreviatedPath(root.path))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .textSelection(.enabled)

                HStack(spacing: 8) {
                    Text(projectRootDetailText(for: root, status: status, skillCount: skillCount))
                        .font(.system(size: 11))
                        .foregroundStyle(status.isUnavailable ? projectRootTint(for: status) : Color.secondary)
                        .lineLimit(1)

                    if let lastScanned = projectRootLastScannedText(for: root, status: status) {
                        Text(lastScanned)
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { root.isEnabled },
                set: { skillStore.setProjectSkillRoot(root, isEnabled: $0) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)

            Menu {
                Button("Refresh Skills") {
                    skillStore.refresh()
                }
                Divider()
                Button(preferredEditor.openMenuTitle) {
                    SkillStore.openProject(root, in: preferredEditor)
                }
                Button("Open .claude/skills") {
                    SkillStore.openProjectSkillsFolder(root, in: preferredEditor)
                }
                .disabled(status == .missingProjectFolder || status == .missingSkillsFolder)
                Button("Reveal in Finder") {
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
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func projectRootPreview(root: ProjectSkillRoot, skillCount: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "checkmark.shield")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.blue)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Add \(root.name)?")
                        .font(.system(size: 13, weight: .semibold))
                    Text("\(projectSkillCountLabel(skillCount)) found in .claude/skills.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Text("SkillsBar will watch this project skill folder for changes. It will not scan the rest of the repo.")
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
                }
                .keyboardShortcut(.defaultAction)

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
        panel.message = "Choose a project folder. SkillsBar will only read .claude/skills inside it."
        panel.prompt = "Choose Project"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let url = panel.url else { return }

        let root = ProjectSkillRoot(path: url.path)
        pendingProjectRoot = root
        pendingProjectSkillCount = SkillScanner().scanClaudeCodeProjectSkills(in: root).count
    }

    private func projectSkillCountLabel(_ count: Int) -> String {
        count == 1 ? "1 skill" : "\(count) skills"
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
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(tint.opacity(secondary ? 0.08 : 0.14))
            .clipShape(Capsule())
    }

    private func countBadge(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(Color.secondary.opacity(0.12))
            .clipShape(Capsule())
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

    private var preferredEditor: ExternalEditor {
        ExternalEditor.resolved(for: preferredEditorRaw)
    }

    private var sectionDivider: some View {
        Divider()
            .overlay(Color.primary.opacity(0.05))
            .padding(.leading, 40)
    }
}
