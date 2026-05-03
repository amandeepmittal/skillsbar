import SwiftUI

struct PluginDetailView: View {
    let plugin: Plugin
    let includedSkills: [Skill]
    let onBack: () -> Void
    let onCopyPath: () -> Void
    let onSelectSkill: (Skill) -> Void

    @AppStorage(AppPreferenceKey.preferredEditor) private var preferredEditorRaw = ExternalEditor.visualStudioCode.rawValue

    private let cardBg = Color.primary.opacity(0.10)
    private let pluginColor = Color.purple
    private var preferredEditor: ExternalEditor {
        ExternalEditor.resolved(for: preferredEditorRaw)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
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

                HStack(spacing: 6) {
                    actionButton(
                        icon: "chevron.left.forwardslash.chevron.right",
                        label: preferredEditor.shortTitle,
                        color: .secondary,
                        action: { SkillStore.openPlugin(plugin, in: preferredEditor) }
                    )
                    actionButton(
                        icon: "doc.on.doc",
                        label: "Copy",
                        color: .secondary,
                        action: copyPath
                    )
                    actionButton(
                        icon: "folder",
                        label: "Reveal",
                        color: .secondary,
                        action: revealInFinder
                    )
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(plugin.displayName)
                            .font(.system(size: 22, weight: .bold))

                        HStack(spacing: 8) {
                            badge("Codex Plugin", color: pluginColor)
                            if let publisher = plugin.publisher, !publisher.isEmpty {
                                badge(publisher, color: .gray)
                            }
                            if let version = plugin.version, !version.isEmpty {
                                badge("v\(version)", color: .blue)
                            }
                        }

                        Button(action: revealInFinder) {
                            HStack(spacing: 6) {
                                Image(systemName: "folder")
                                    .font(.system(size: 12))
                                Text(plugin.path)
                                    .font(.system(size: 12, design: .monospaced))
                                    .lineLimit(2)
                            }
                            .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .onHover { hovering in
                            if hovering {
                                NSCursor.pointingHand.push()
                            } else {
                                NSCursor.pop()
                            }
                        }
                        .help("Reveal in Finder")

                        if let modified = plugin.formattedLastModified {
                            HStack(spacing: 6) {
                                Image(systemName: "clock")
                                    .font(.system(size: 11))
                                Text("Modified \(modified)")
                                    .font(.system(size: 12))
                            }
                            .foregroundStyle(.secondary)
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(cardBg)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                    VStack(alignment: .leading, spacing: 8) {
                        Text("DESCRIPTION")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .tracking(0.5)

                        if !plugin.description.isEmpty {
                            Text(plugin.description)
                                .font(.system(size: 14))
                                .lineSpacing(3)
                        } else {
                            Text("No description available.")
                                .font(.system(size: 14))
                                .foregroundStyle(.secondary)
                                .italic()
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(cardBg)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                    if !plugin.capabilities.isEmpty || !plugin.keywords.isEmpty || plugin.defaultPrompt != nil || plugin.authorName != nil {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("PLUGIN METADATA")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .tracking(0.5)

                            if let authorName = plugin.authorName, !authorName.isEmpty {
                                metadataRow(title: "Author", value: authorName)
                            }

                            if let defaultPrompt = plugin.defaultPrompt, !defaultPrompt.isEmpty {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Default prompt")
                                        .font(.system(size: 13))
                                        .foregroundStyle(.secondary)
                                    Text(defaultPrompt)
                                        .font(.system(size: 13))
                                }
                            }

                            if !plugin.capabilities.isEmpty {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Capabilities")
                                        .font(.system(size: 13))
                                        .foregroundStyle(.secondary)

                                    WrappingHStack(items: plugin.capabilities) { capability in
                                        Text(capability)
                                            .font(.system(size: 11, weight: .medium))
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(Color.primary.opacity(0.05))
                                            .clipShape(Capsule())
                                    }
                                }
                            }

                            if !plugin.keywords.isEmpty {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Keywords")
                                        .font(.system(size: 13))
                                        .foregroundStyle(.secondary)

                                    WrappingHStack(items: plugin.keywords) { keyword in
                                        Text(keyword)
                                            .font(.system(size: 11, weight: .medium))
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(Color.primary.opacity(0.05))
                                            .clipShape(Capsule())
                                    }
                                }
                            }
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(cardBg)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("INCLUDED SKILLS")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .tracking(0.5)

                        if includedSkills.isEmpty {
                            Text("No plugin skills were discovered from this install.")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(Array(includedSkills.enumerated()), id: \.element.id) { index, skill in
                                if index > 0 {
                                    Divider()
                                }

                                Button {
                                    onSelectSkill(skill)
                                } label: {
                                    HStack(spacing: 10) {
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(skill.displayName)
                                                .font(.system(size: 14, weight: .medium))
                                                .foregroundStyle(.primary)
                                                .lineLimit(1)

                                            if !skill.shortDescription.isEmpty {
                                                Text(skill.shortDescription)
                                                    .font(.system(size: 12))
                                                    .foregroundStyle(.secondary)
                                                    .lineLimit(2)
                                            }
                                        }

                                        Spacer()

                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 11, weight: .semibold))
                                            .foregroundStyle(.tertiary)
                                    }
                                    .padding(.vertical, 8)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(cardBg)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(14)
            }
        }
        .frame(width: SkillsBarLayout.windowWidth, height: SkillsBarLayout.detailHeight)
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    private func metadataRow(title: String, value: String) -> some View {
        HStack(spacing: 6) {
            Text("\(title):")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 13))
        }
    }

    private func copyPath() {
        onCopyPath()
    }

    private func revealInFinder() {
        NSWorkspace.shared.selectFile(plugin.path, inFileViewerRootedAtPath: "")
    }

    private func actionButton(icon: String, label: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: icon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 16, height: 16)
                Text(label)
                    .font(.system(size: 9, weight: .medium))
            }
            .frame(width: 46, height: 36)
            .foregroundStyle(color)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
