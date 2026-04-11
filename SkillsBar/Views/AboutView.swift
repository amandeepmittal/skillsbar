import SwiftUI

struct AboutView: View {
    @ObservedObject var skillStore: SkillStore
    let onBack: () -> Void
    private let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.6.9"
    private let heroCornerRadius: CGFloat = 22
    private let sectionCornerRadius: CGFloat = 16

    var body: some View {
        VStack(spacing: 0) {
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
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            Divider()

            ScrollView {
                VStack(spacing: 14) {
                    heroCard

                    infoSection(icon: "square.grid.2x2", title: "Library Snapshot") {
                        HStack(spacing: 10) {
                            statPill(value: "\(skillStore.totalSkillCount)", label: "Skills")
                            statPill(value: "\(skillStore.plugins.count)", label: "Plugins")
                            statPill(value: "\(agentCount)", label: "Agents")
                            statPill(value: "\(skillStore.collections.count)", label: "Collections")
                        }
                    }

                    infoSection(icon: "folder", title: "Watched Directories") {
                        VStack(spacing: 0) {
                            directoryRow("~/.claude/skills/")
                            sectionDivider
                            directoryRow("~/.claude/plugins/cache/")
                            sectionDivider
                            directoryRow("~/.claude/agents/")
                            sectionDivider
                            directoryRow("~/.codex/skills/")
                            sectionDivider
                            directoryRow("~/.codex/plugins/cache/")
                        }
                    }

                    infoSection(icon: "keyboard", title: "Keyboard Shortcut") {
                        Text("Option + Shift + S")
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundStyle(.primary)
                    }

                    sortCard

                    footerLinks
                }
                .padding(.horizontal, 16)
                .padding(.top, 18)
                .padding(.bottom, 18)
                .frame(maxWidth: .infinity, alignment: .top)
            }
        }
        .frame(width: SkillsBarLayout.windowWidth, height: SkillsBarLayout.aboutHeight)
    }

    private var heroCard: some View {
        VStack(spacing: 16) {
            if let icon = NSApp.applicationIconImage {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 96, height: 96)
                    .clipShape(RoundedRectangle(cornerRadius: 22))
                    .shadow(color: Color.blue.opacity(0.14), radius: 18, y: 8)
            }

            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    Text("SkillsBar")
                        .font(.system(size: 28, weight: .bold))

                    Text("v\(appVersion)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.65))
                        .clipShape(Capsule())
                }

                Text("Browse Claude Code and Codex CLI skills, plugins, agents, and collections right from your menu bar.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
                    .lineSpacing(2)
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(
                colors: [
                    Color.blue.opacity(0.14),
                    Color.blue.opacity(0.05)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .overlay(
            RoundedRectangle(cornerRadius: heroCornerRadius)
                .stroke(Color.blue.opacity(0.10), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: heroCornerRadius))
    }

    private var agentCount: Int {
        skillStore.agentGroups.reduce(0) { $0 + $1.totalCount }
    }

    private var sortCard: some View {
        infoSection(icon: "arrow.up.arrow.down", title: "Default Sort") {
            Picker("", selection: $skillStore.sortOption) {
                ForEach(SkillSortOption.allCases, id: \.self) { option in
                    Text(option.rawValue).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    private var footerLinks: some View {
        HStack(spacing: 14) {
            footerLink(
                title: "GitHub",
                systemImage: "link",
                urlString: "https://github.com/amandeepmittal/skillsbar"
            )

            footerSeparator

            footerLink(
                title: "amanhimself.dev",
                systemImage: "globe",
                urlString: "https://amanhimself.dev"
            )

            footerSeparator

            footerLink(
                title: "Aman Mittal",
                systemImage: "person.crop.circle",
                urlString: "https://amanhimself.dev"
            )
        }
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(.secondary)
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity)
        .background(Color.primary.opacity(0.05))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func infoSection<Content: View>(icon: String, title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Text(title.uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .tracking(0.5)
            }

            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.05))
        .overlay(
            RoundedRectangle(cornerRadius: sectionCornerRadius)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: sectionCornerRadius))
    }

    private func statPill(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .monospaced))
                .foregroundStyle(.primary)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color.primary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func directoryRow(_ path: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(Color.blue.opacity(0.45))
                .frame(width: 5, height: 5)
                .padding(.top, 5)

            Text(path)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.primary)
                .textSelection(.enabled)
        }
        .padding(.vertical, 8)
    }

    private var footerSeparator: some View {
        Circle()
            .fill(Color.secondary.opacity(0.25))
            .frame(width: 4, height: 4)
    }

    private var sectionDivider: some View {
        Divider()
            .overlay(Color.primary.opacity(0.05))
            .padding(.leading, 15)
    }

    private func footerLink(title: String, systemImage: String, urlString: String) -> some View {
        Button {
            if let url = URL(string: urlString) {
                NSWorkspace.shared.open(url)
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .semibold))
                Text(title)
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
    }
}
