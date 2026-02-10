import SwiftUI

struct SkillRowView: View {
    let skill: Skill
    let isPinned: Bool
    @State private var isHovered = false

    private var hoverColor: Color {
        switch skill.source {
        case .claudeCode: return Color(red: 0.85, green: 0.45, blue: 0.1)
        case .codexCLI: return .purple
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(skill.source.iconName)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 18, height: 18)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(skill.displayName)
                        .font(.system(size: 14, weight: .medium))
                        .lineLimit(1)
                    if skill.isNew {
                        Text("NEW")
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.15))
                            .foregroundStyle(.blue)
                            .clipShape(Capsule())
                    }
                }

                if !skill.shortDescription.isEmpty {
                    Text(skill.shortDescription)
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
