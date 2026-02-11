import SwiftUI

private let cardBackground = Color.primary.opacity(0.10)
private let cardRadius: CGFloat = 12

struct UsageStatsView: View {
    @ObservedObject var usageTracker: UsageTracker
    let installedSkillNames: Set<String>
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

                Text("Usage Stats")
                    .font(.system(size: 16, weight: .bold))

                Spacer()

                Button(action: { usageTracker.refresh() }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 13))
                        .rotationEffect(.degrees(usageTracker.isLoading ? 360 : 0))
                        .animation(usageTracker.isLoading ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: usageTracker.isLoading)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Refresh stats")
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            Divider()

            if usageTracker.stats.isEmpty && !usageTracker.isLoading {
                emptyState
            } else {
                ScrollView {
                    VStack(spacing: 10) {
                        summaryCard
                        insightsCard
                        rankedListCard
                    }
                    .padding(14)
                }
            }
        }
        .frame(width: 440, height: 620)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "chart.bar")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text("No Usage Data")
                .font(.system(size: 16, weight: .semibold))
            Text("Skill invocations from Claude Code session transcripts will appear here once you start using skills.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Summary Card

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SUMMARY")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .tracking(0.5)

            HStack(spacing: 0) {
                statItem(value: "\(usageTracker.totalInvocations)", label: "Total Uses")
                Divider().frame(height: 30)
                statItem(value: "\(usageTracker.stats.count)", label: "Skills Used")
                Divider().frame(height: 30)
                statItem(value: dateRange, label: "Date Range")
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: cardRadius))
    }

    private var dateRange: String {
        let allStats = usageTracker.rankedStats
        guard let earliest = allStats.compactMap({ $0.firstUsedDate }).min(),
              let latest = allStats.compactMap({ $0.lastUsedDate }).max() else {
            return "--"
        }
        let days = Calendar.current.dateComponents([.day], from: earliest, to: latest).day ?? 0
        if days == 0 { return "Today" }
        if days < 7 { return "\(days)d" }
        if days < 30 { return "\(days / 7)w" }
        return "\(days / 30)mo"
    }

    // MARK: - Insights Card

    private var insightsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("INSIGHTS")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .tracking(0.5)

            if let top = usageTracker.mostUsed {
                insightRow(
                    icon: "crown.fill",
                    color: .yellow,
                    label: "Most used",
                    value: "/\(top.skillName) (\(top.totalCount)x)"
                )
            }

            if let latest = usageTracker.rankedStats.compactMap({ stat in
                stat.lastUsedDate.map { (stat, $0) }
            }).max(by: { $0.1 < $1.1 }) {
                insightRow(
                    icon: "clock.fill",
                    color: .blue,
                    label: "Last used",
                    value: "/\(latest.0.skillName) \(relativeDate(latest.1))"
                )
            }

            let stale = usageTracker.staleSkills
            if !stale.isEmpty {
                insightRow(
                    icon: "exclamationmark.triangle.fill",
                    color: .orange,
                    label: "Stale (\(stale.count))",
                    value: stale.map { "/\($0.skillName)" }.joined(separator: ", ")
                )
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: cardRadius))
    }

    private func insightRow(icon: String, color: Color, label: String, value: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(color)
                .frame(width: 16)
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)
            Text(value)
                .font(.system(size: 12))
                .lineLimit(1)
        }
    }

    // MARK: - Ranked List

    private var rankedListCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ALL SKILLS")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .tracking(0.5)

            ForEach(Array(usageTracker.rankedStats.enumerated()), id: \.element.id) { index, stat in
                if index > 0 {
                    Divider()
                }
                HStack(spacing: 10) {
                    Text("#\(index + 1)")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .frame(width: 26, alignment: .leading)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text("/\(stat.skillName)")
                                .font(.system(size: 13, weight: .medium))
                            if !installedSkillNames.contains(stat.skillName) {
                                Text("not installed")
                                    .font(.system(size: 9, weight: .medium))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(Color.secondary.opacity(0.15))
                                    .foregroundStyle(.secondary)
                                    .clipShape(Capsule())
                            }
                        }
                        if let lastUsed = stat.lastUsedDate {
                            Text("Last used \(relativeDate(lastUsed))")
                                .font(.system(size: 11))
                                .foregroundStyle(.tertiary)
                        }
                    }

                    Spacer()

                    Text("\(stat.totalCount)x")
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: cardRadius))
    }

    // MARK: - Helpers

    private func statItem(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .monospaced))
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func relativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
