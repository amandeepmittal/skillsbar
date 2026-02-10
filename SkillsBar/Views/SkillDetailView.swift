import SwiftUI

struct SkillDetailView: View {
    let skill: Skill
    let isPinned: Bool
    let onBack: () -> Void
    let onDelete: (Skill) -> Void
    let onTogglePin: (Skill) -> Void

    @State private var showDeleteConfirmation = false
    @State private var showFullContent = false

    private let cardBg = Color.primary.opacity(0.10)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header bar
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

                // Action buttons
                HStack(spacing: 6) {
                    actionButton(
                        icon: isPinned ? "star.fill" : "star",
                        label: isPinned ? "Unpin" : "Pin",
                        color: isPinned ? .yellow : .secondary,
                        action: { onTogglePin(skill) }
                    )
                    actionButton(
                        icon: "chevron.left.forwardslash.chevron.right",
                        label: "VS Code",
                        color: .secondary,
                        action: { SkillStore.openInVSCode(skill) }
                    )
                    actionButton(
                        icon: "square.and.pencil",
                        label: "Editor",
                        color: .secondary,
                        action: { SkillStore.openInDefaultEditor(skill) }
                    )
                    actionButton(
                        icon: "doc.on.doc",
                        label: "Copy",
                        color: .secondary,
                        action: copyPath
                    )
                    actionButton(
                        icon: "trash",
                        label: "Delete",
                        color: .red.opacity(0.8),
                        action: { showDeleteConfirmation = true }
                    )
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    // Title and badges card
                    VStack(alignment: .leading, spacing: 10) {
                        Text(skill.displayName)
                            .font(.system(size: 22, weight: .bold))

                        HStack(spacing: 8) {
                            badge(skill.source.groupTitle, color: badgeColor)
                            badge(skill.source.sectionTitle, color: .gray)
                            if let version = skill.version {
                                badge("v\(version)", color: .blue)
                            }
                        }

                        // Path (click to reveal in Finder)
                        Button(action: revealInFinder) {
                            HStack(spacing: 6) {
                                Image(systemName: "folder")
                                    .font(.system(size: 12))
                                Text(skill.path)
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

                        // Last modified
                        if let modified = skill.formattedLastModified {
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

                    // Description card
                    VStack(alignment: .leading, spacing: 8) {
                        Text("DESCRIPTION")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .tracking(0.5)

                        if !skill.description.isEmpty {
                            if let attributed = try? AttributedString(markdown: skill.description) {
                                Text(attributed)
                                    .font(.system(size: 14))
                                    .lineSpacing(3)
                            } else {
                                Text(skill.description)
                                    .font(.system(size: 14))
                                    .lineSpacing(3)
                            }
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

                    // How to use card
                    VStack(alignment: .leading, spacing: 8) {
                        Text("HOW TO USE")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .tracking(0.5)

                        HStack(spacing: 0) {
                            Text(skill.triggerCommand)
                                .font(.system(size: 15, weight: .medium, design: .monospaced))
                                .textSelection(.enabled)
                            Spacer()
                            Button {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(skill.triggerCommand, forType: .string)
                            } label: {
                                Image(systemName: "doc.on.doc")
                                    .font(.system(size: 12))
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                            .help("Copy command")
                        }
                        .padding(10)
                        .background(Color.primary.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                        Text(skill.triggerHint)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(cardBg)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                    // Full content preview card
                    if !skill.body.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    showFullContent.toggle()
                                }
                            } label: {
                                HStack {
                                    Text("FULL CONTENT")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(.secondary)
                                        .tracking(0.5)
                                    Spacer()
                                    Image(systemName: showFullContent ? "chevron.up" : "chevron.down")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .buttonStyle(.plain)

                            if showFullContent {
                                Text(skill.body)
                                    .font(.system(size: 13, design: .monospaced))
                                    .lineSpacing(2)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(cardBg)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    // Folder contents card
                    if !skill.folderContents.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("FILES")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .tracking(0.5)

                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(skill.folderContents, id: \.self) { file in
                                    HStack(spacing: 6) {
                                        Image(systemName: fileIcon(for: file))
                                            .font(.system(size: 11))
                                            .foregroundStyle(.secondary)
                                            .frame(width: 16)
                                        Text(file)
                                            .font(.system(size: 12, design: .monospaced))
                                    }
                                }
                            }
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(cardBg)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
                .padding(14)
            }
        }
        .frame(width: 440, height: 620)
        .alert("Delete Skill", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                onDelete(skill)
                onBack()
            }
        } message: {
            Text("Delete \"\(skill.displayName)\"? This will remove the entire skill folder and cannot be undone.")
        }
    }

    private var badgeColor: Color {
        switch skill.source.badgeColor {
        case "purple": return .purple
        case "blue": return .blue
        case "green": return .green
        case "orange": return .orange
        default: return .gray
        }
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

    private func copyPath() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(skill.path, forType: .string)
    }

    private func revealInFinder() {
        NSWorkspace.shared.selectFile(skill.path, inFileViewerRootedAtPath: "")
    }

    private func actionButton(icon: String, label: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                Text(label)
                    .font(.system(size: 9, weight: .medium))
            }
            .frame(width: 46, height: 36)
            .foregroundStyle(color)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func fileIcon(for filename: String) -> String {
        let ext = (filename as NSString).pathExtension.lowercased()
        switch ext {
        case "md": return "doc.text"
        case "yaml", "yml": return "gearshape"
        case "json": return "curlybraces"
        case "swift", "py", "js", "ts": return "chevron.left.forwardslash.chevron.right"
        case "txt": return "doc.plaintext"
        default:
            if filename.hasPrefix(".") { return "eye.slash" }
            return "doc"
        }
    }
}
