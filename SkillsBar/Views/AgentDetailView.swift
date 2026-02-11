import SwiftUI

struct AgentDetailView: View {
    let agent: Agent
    let isPinned: Bool
    let onBack: () -> Void
    let onDelete: (Agent) -> Void
    let onTogglePin: (Agent) -> Void

    @State private var showDeleteConfirmation = false
    @State private var showFullContent = false

    private let cardBg = Color.primary.opacity(0.10)
    private let agentColor = Color(red: 0.0, green: 0.45, blue: 0.5)

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
                        action: { onTogglePin(agent) }
                    )
                    actionButton(
                        icon: "chevron.left.forwardslash.chevron.right",
                        label: "VS Code",
                        color: .secondary,
                        action: { SkillStore.openAgentInVSCode(agent) }
                    )
                    actionButton(
                        icon: "square.and.pencil",
                        label: "Editor",
                        color: .secondary,
                        action: { SkillStore.openAgentInDefaultEditor(agent) }
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
                        Text(agent.displayName)
                            .font(.system(size: 22, weight: .bold))

                        HStack(spacing: 8) {
                            badge("Agents", color: agentColor)
                            badge(agent.source.sectionTitle, color: .gray)
                            if let model = agent.model, model != .inherit {
                                badge(model.displayName, color: Color(red: 0.0, green: 0.45, blue: 0.5))
                            }
                        }

                        // Path (click to reveal in Finder)
                        Button(action: revealInFinder) {
                            HStack(spacing: 6) {
                                Image(systemName: "doc.text")
                                    .font(.system(size: 12))
                                Text(agent.path)
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
                        if let modified = agent.formattedLastModified {
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

                        if !agent.description.isEmpty {
                            if let attributed = try? AttributedString(markdown: agent.description) {
                                Text(attributed)
                                    .font(.system(size: 14))
                                    .lineSpacing(3)
                            } else {
                                Text(agent.description)
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

                    // Agent Configuration card
                    if agent.model != nil || agent.color != nil || !agent.tools.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("AGENT CONFIGURATION")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .tracking(0.5)

                            if let model = agent.model {
                                HStack(spacing: 6) {
                                    Text("Model:")
                                        .font(.system(size: 13))
                                        .foregroundStyle(.secondary)
                                    badge(model.displayName, color: Color(red: 0.0, green: 0.45, blue: 0.5))
                                }
                            }

                            if let agentColor = agent.color {
                                HStack(spacing: 6) {
                                    Text("Color:")
                                        .font(.system(size: 13))
                                        .foregroundStyle(.secondary)
                                    Circle()
                                        .fill(agentColor.swiftUIColor)
                                        .frame(width: 10, height: 10)
                                    Text(agentColor.rawValue.capitalized)
                                        .font(.system(size: 13))
                                }
                            }

                            if !agent.tools.isEmpty {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Tools:")
                                        .font(.system(size: 13))
                                        .foregroundStyle(.secondary)

                                    WrappingHStack(items: agent.tools) { tool in
                                        Text(tool)
                                            .font(.system(size: 11, weight: .medium, design: .monospaced))
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

                    // How It Works card
                    VStack(alignment: .leading, spacing: 8) {
                        Text("HOW IT WORKS")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .tracking(0.5)

                        HStack(spacing: 0) {
                            Text(agent.identifier)
                                .font(.system(size: 15, weight: .medium, design: .monospaced))
                                .textSelection(.enabled)
                            Spacer()
                            Button {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(agent.identifier, forType: .string)
                            } label: {
                                Image(systemName: "doc.on.doc")
                                    .font(.system(size: 12))
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                            .help("Copy identifier")
                        }
                        .padding(10)
                        .background(Color.primary.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                        Text("Agents are used automatically by Claude Code based on their description. They cannot be invoked directly.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(cardBg)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                    // Full content preview card
                    if !agent.body.isEmpty {
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
                                Text(agent.body)
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
                }
                .padding(14)
            }
        }
        .frame(width: 440, height: 620)
        .alert("Delete Agent", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                onDelete(agent)
                onBack()
            }
        } message: {
            Text("Delete \"\(agent.displayName)\"? This will remove the agent file and cannot be undone.")
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
        NSPasteboard.general.setString(agent.path, forType: .string)
    }

    private func revealInFinder() {
        NSWorkspace.shared.selectFile(agent.path, inFileViewerRootedAtPath: "")
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
}

// MARK: - Wrapping HStack for tools badges

struct WrappingHStack<Item: Hashable, Content: View>: View {
    let items: [Item]
    let content: (Item) -> Content

    var body: some View {
        FlowLayout(spacing: 4) {
            ForEach(items, id: \.self) { item in
                content(item)
            }
        }
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = layoutSubviews(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layoutSubviews(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }

    private func layoutSubviews(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var totalWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)

            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }

            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            totalWidth = max(totalWidth, x - spacing)
        }

        totalHeight = y + rowHeight
        return (CGSize(width: totalWidth, height: totalHeight), positions)
    }
}
