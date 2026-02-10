import SwiftUI

private let claudeColor = Color(red: 0.85, green: 0.45, blue: 0.1)
private let codexColor = Color.purple
private let cardBackground = Color.primary.opacity(0.10)
private let cardRadius: CGFloat = 12

struct MenuBarView: View {
    @ObservedObject var store: SkillStore
    @State private var selectedSkill: Skill?
    @State private var selectedTab: SkillStore.SkillTab = .claudeCode
    @State private var showAbout = false

    var body: some View {
        Group {
            if showAbout {
                AboutView(onBack: { showAbout = false })
            } else if let skill = selectedSkill {
                SkillDetailView(
                    skill: skill,
                    isPinned: store.isPinned(skill),
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
    }

    private var mainListView: some View {
        VStack(spacing: 8) {
            // Header
            HStack {
                Text("SkillsBar")
                    .font(.system(size: 16, weight: .bold))
                Spacer()
                Text("\(store.totalSkillCount) skills")
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

            // Skill list for selected tab
            let tabGroups = store.groupsForTab(selectedTab)
            if tabGroups.isEmpty {
                emptyStateView
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(tabGroups) { group in
                            ForEach(group.sections) { section in
                                // Each section is its own card
                                VStack(alignment: .leading, spacing: 0) {
                                    // Section header
                                    if group.sections.count > 1 || group.id == "pinned" {
                                        HStack(spacing: 5) {
                                            if group.id == "pinned" {
                                                Image(systemName: "star.fill")
                                                    .font(.system(size: 10))
                                                    .foregroundStyle(.yellow)
                                            }
                                            Text(section.title.uppercased())
                                                .font(.system(size: 11, weight: .semibold))
                                                .foregroundStyle(.secondary)
                                                .tracking(0.5)
                                        }
                                        .padding(.horizontal, 12)
                                        .padding(.top, 10)
                                        .padding(.bottom, 4)
                                    }

                                    ForEach(Array(section.skills.enumerated()), id: \.element.id) { index, skill in
                                        if index > 0 {
                                            Divider()
                                                .padding(.leading, 44)
                                        }
                                        Button(action: { selectedSkill = skill }) {
                                            SkillRowView(
                                                skill: skill,
                                                isPinned: store.isPinned(skill)
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
                                .background(cardBackground)
                                .clipShape(RoundedRectangle(cornerRadius: cardRadius))
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                }
                .frame(maxHeight: 600)
            }

            // Footer card
            HStack {
                Button(action: { store.refresh() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12))
                        Text("Refresh")
                            .font(.system(size: 12))
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Refresh skills")

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

    private var emptyStateView: some View {
        VStack(spacing: 10) {
            if store.searchText.isEmpty {
                Image(systemName: "tray")
                    .font(.system(size: 28))
                    .foregroundStyle(.secondary)
                Text("No \(selectedTab.rawValue) skills found")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)

                // Tab-specific guidance
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
}
