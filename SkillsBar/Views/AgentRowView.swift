import SwiftUI

struct AgentRowView: View {
    let agent: Agent
    let isPinned: Bool
    @State private var isHovered = false

    private let hoverColor = Color(red: 0.0, green: 0.45, blue: 0.5)

    var body: some View {
        HStack(spacing: 12) {
            Image("ClaudeLogo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 18, height: 18)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(agent.displayName)
                        .font(.system(size: 14, weight: .medium))
                        .lineLimit(1)
                    if agent.isNew {
                        Text("NEW")
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.15))
                            .foregroundStyle(.blue)
                            .clipShape(Capsule())
                    }
                    if let model = agent.model, model != .inherit {
                        Text(model.displayName)
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color(red: 0.0, green: 0.45, blue: 0.5).opacity(0.2))
                            .foregroundStyle(Color(red: 0.0, green: 0.45, blue: 0.5))
                            .clipShape(Capsule())
                    }
                    if let agentColor = agent.color {
                        Circle()
                            .fill(agentColor.swiftUIColor)
                            .frame(width: 8, height: 8)
                    }
                }

                if !agent.shortDescription.isEmpty {
                    Text(agent.shortDescription)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer()

            if isPinned {
                Image(systemName: "star.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.yellow)
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(isHovered ? hoverColor.opacity(0.08) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
        }
    }
}
