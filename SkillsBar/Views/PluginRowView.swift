import SwiftUI

struct PluginRowView: View {
    let plugin: Plugin
    let skillCount: Int
    @State private var isHovered = false

    private let hoverColor = Color.purple

    var body: some View {
        HStack(spacing: 12) {
            Image(plugin.source.iconName)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 18, height: 18)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(plugin.displayName)
                        .font(.system(size: 14, weight: .medium))
                        .lineLimit(1)

                    if let version = plugin.version, !version.isEmpty {
                        Text("v\(version)")
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.15))
                            .foregroundStyle(.blue)
                            .clipShape(Capsule())
                    }

                    if skillCount > 0 {
                        Text("\(skillCount) skills")
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(hoverColor.opacity(0.16))
                            .foregroundStyle(hoverColor)
                            .clipShape(Capsule())
                    }
                }

                if !plugin.shortDescription.isEmpty {
                    Text(plugin.shortDescription)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                } else if let publisher = plugin.publisher, !publisher.isEmpty {
                    Text(publisher)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

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
