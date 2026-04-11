import SwiftUI

struct SettingsView: View {
    @ObservedObject var skillStore: SkillStore
    let onBack: () -> Void

    @AppStorage(AppPreferenceKey.showsWhatsNewSection) private var showsWhatsNewSection = true
    @AppStorage(AppPreferenceKey.preferredAppearance) private var preferredAppearanceRaw = AppAppearance.system.rawValue

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

                Text("Settings")
                    .font(.system(size: 16, weight: .semibold))

                Spacer()

                Color.clear
                    .frame(width: 44, height: 1)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            Divider()

            ScrollView {
                VStack(spacing: 14) {
                    infoSection(icon: "sparkles", title: "Discover") {
                        Toggle(isOn: $showsWhatsNewSection) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Show What's New")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(.primary)
                                Text("Highlight skills and plugins changed in the last 7 days.")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .toggleStyle(.switch)
                    }

                    infoSection(icon: "circle.lefthalf.filled", title: "Appearance") {
                        VStack(alignment: .leading, spacing: 10) {
                            Picker("", selection: $preferredAppearanceRaw) {
                                ForEach(AppAppearance.allCases) { appearance in
                                    Text(appearance.title).tag(appearance.rawValue)
                                }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()

                            Text("Choose whether SkillsBar follows your Mac appearance or stays fixed in light or dark mode.")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                    }

                    infoSection(icon: "arrow.up.arrow.down", title: "Default Sort") {
                        VStack(alignment: .leading, spacing: 10) {
                            Picker("", selection: $skillStore.sortOption) {
                                ForEach(SkillSortOption.allCases, id: \.self) { option in
                                    Text(option.rawValue).tag(option)
                                }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()

                            Text("Applies to the main skill lists across Claude Code and Codex.")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                    }

                    infoSection(icon: "bolt", title: "Behavior") {
                        Text("Changes apply instantly and are remembered across launches.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 18)
                .padding(.bottom, 18)
                .frame(maxWidth: .infinity, alignment: .top)
            }
        }
        .frame(width: SkillsBarLayout.windowWidth, height: SkillsBarLayout.aboutHeight)
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
}
