import SwiftUI

struct AboutView: View {
    let onBack: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header
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

            VStack(spacing: 20) {
                Spacer()

                // App icon
                if let icon = NSApp.applicationIconImage {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 80, height: 80)
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                }

                // App name and version
                VStack(spacing: 4) {
                    Text("SkillsBar")
                        .font(.system(size: 22, weight: .bold))
                    Text("Version 1.2.4")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }

                // Description
                Text("A macOS menu bar app for browsing and managing your Claude Code and Codex CLI skills and agents.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)

                // Info cards
                VStack(spacing: 8) {
                    infoCard(
                        icon: "folder",
                        title: "Watched Directories",
                        items: [
                            "~/.claude/skills/",
                            "~/.claude/plugins/cache/",
                            "~/.codex/skills/",
                            "~/.claude/agents/"
                        ]
                    )

                    infoCard(
                        icon: "keyboard",
                        title: "Keyboard Shortcut",
                        items: ["Option + Shift + S"]
                    )
                }
                .padding(.horizontal, 20)

                // Links
                HStack(spacing: 20) {
                    Button {
                        if let url = URL(string: "https://github.com/amandeepmittal/skillsbar") {
                            NSWorkspace.shared.open(url)
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "link")
                                .font(.system(size: 12))
                            Text("GitHub")
                                .font(.system(size: 13))
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.blue)
                }

                Spacer()

                VStack(spacing: 4) {
                    Text("Built with SwiftUI by")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                    Button {
                        if let url = URL(string: "https://amanhimself.dev") {
                            NSWorkspace.shared.open(url)
                        }
                    } label: {
                        Text("Aman Mittal")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.blue)
                }
                .padding(.bottom, 16)
            }
        }
        .frame(width: 440, height: 620)
    }

    private func infoCard(icon: String, title: String, items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Text(title.uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .tracking(0.5)
            }

            ForEach(items, id: \.self) { item in
                Text(item)
                    .font(.system(size: 12, design: .monospaced))
                    .textSelection(.enabled)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
