import SwiftUI

struct SettingsView: View {
    @ObservedObject var skillStore: SkillStore
    let onBack: () -> Void

    @AppStorage(AppPreferenceKey.showsWhatsNewSection) private var showsWhatsNewSection = true
    @AppStorage(AppPreferenceKey.preferredAppearance) private var preferredAppearanceRaw = AppAppearance.system.rawValue
    @AppStorage(AppPreferenceKey.preferredEditor) private var preferredEditorRaw = ExternalEditor.visualStudioCode.rawValue
    @StateObject private var loginItemController = LoginItemController()
    @State private var installedEditors = ExternalEditor.installedEditors

    private let sectionCornerRadius: CGFloat = 16
    private var startAtLoginBinding: Binding<Bool> {
        Binding(
            get: { loginItemController.isEnabled },
            set: { loginItemController.setEnabled($0) }
        )
    }

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

                    infoSection(icon: "bolt", title: "Start at Login") {
                        VStack(alignment: .leading, spacing: 10) {
                            Toggle(isOn: startAtLoginBinding) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Open Automatically")
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(.primary)
                                    Text("Open SkillsBar automatically when you sign in.")
                                        .font(.system(size: 12))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .toggleStyle(.switch)

                            if loginItemController.requiresApproval {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Allow SkillsBar in System Settings to finish enabling Start at Login.")
                                        .font(.system(size: 12))
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)

                                    Button("Open Login Items Settings") {
                                        loginItemController.openLoginItemsSettings()
                                    }
                                    .font(.system(size: 12))
                                }
                            }

                            if let errorMessage = loginItemController.errorMessage {
                                Text(errorMessage)
                                    .font(.system(size: 12))
                                    .foregroundStyle(.red)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }

                    infoSection(icon: "chevron.left.forwardslash.chevron.right", title: "Editor") {
                        VStack(alignment: .leading, spacing: 10) {
                            if installedEditors.isEmpty {
                                Text("No supported editors were found. Install VS Code, WebStorm, Cursor, Zed, or another supported editor to choose it here.")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            } else {
                                Picker("", selection: $preferredEditorRaw) {
                                    ForEach(installedEditors) { editor in
                                        Text(editor.title).tag(editor.rawValue)
                                    }
                                }
                                .pickerStyle(.menu)
                                .labelsHidden()

                                Text("Choose which installed editor opens skills, agents, plugins, and global instructions.")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
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
                }
                .padding(.horizontal, 16)
                .padding(.top, 18)
                .padding(.bottom, 18)
                .frame(maxWidth: .infinity, alignment: .top)
            }
        }
        .frame(width: SkillsBarLayout.windowWidth, height: SkillsBarLayout.aboutHeight)
        .onAppear {
            loginItemController.refresh()
            refreshInstalledEditors()
        }
    }

    private func refreshInstalledEditors() {
        installedEditors = ExternalEditor.installedEditors

        guard !installedEditors.isEmpty else {
            return
        }

        if !installedEditors.contains(where: { $0.rawValue == preferredEditorRaw }) {
            preferredEditorRaw = ExternalEditor.defaultEditor.rawValue
        }
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
