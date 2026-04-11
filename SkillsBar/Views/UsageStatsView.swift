import SwiftUI

private let cardBackground = Color.primary.opacity(0.10)
private let cardRadius: CGFloat = 12
private let maxDisplayedSkillsPerSource = 10

struct UsageStatsView: View {
    @ObservedObject var usageTracker: UsageTracker
    let installedSkillIdentifiers: Set<String>
    let onBack: () -> Void

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

                Text("Usage Stats")
                    .font(.system(size: 16, weight: .bold))

                Spacer()

                Button(action: { usageTracker.refresh() }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 13))
                        .rotationEffect(.degrees(usageTracker.isLoading ? 360 : 0))
                        .animation(
                            usageTracker.isLoading
                                ? .linear(duration: 1).repeatForever(autoreverses: false)
                                : .default,
                            value: usageTracker.isLoading
                        )
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
        .frame(width: SkillsBarLayout.windowWidth, height: SkillsBarLayout.detailHeight)
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
            Text("Claude Code session transcripts and explicit Codex skill triggers, including plugin skills, will appear here once you start using skills.")
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
        VStack(alignment: .leading, spacing: 10) {
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

            if !usageTracker.sourcesWithStats.isEmpty {
                Text("BY SOURCE")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .tracking(0.5)

                HStack(spacing: 8) {
                    ForEach(usageTracker.sourcesWithStats, id: \.self) { source in
                        sourceSummaryItem(source)
                    }
                }
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
                    value: "\(top.displayCommand) (\(top.totalCount)x)",
                    source: top.source
                )
            }

            if let latest = usageTracker.rankedStats.compactMap({ stat in
                stat.lastUsedDate.map { (stat, $0) }
            }).max(by: { $0.1 < $1.1 }) {
                insightRow(
                    icon: "clock.fill",
                    color: .blue,
                    label: "Last used",
                    value: "\(latest.0.displayCommand) \(relativeDate(latest.1))",
                    source: latest.0.source
                )
            }

            let stale = usageTracker.staleSkills
            if !stale.isEmpty {
                insightRow(
                    icon: "exclamationmark.triangle.fill",
                    color: .orange,
                    label: "Stale (\(stale.count))",
                    value: stale.prefix(3).map(\.displayCommand).joined(separator: ", "),
                    source: stale.first?.source
                )
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: cardRadius))
    }

    private func insightRow(icon: String, color: Color, label: String, value: String, source: UsageSource?) -> some View {
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
            Spacer(minLength: 0)
            if let source {
                sourceTag(source)
            }
        }
    }

    // MARK: - Ranked List

    private var rankedListCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ALL SKILLS")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .tracking(0.5)

            ForEach(usageTracker.sourcesWithStats, id: \.self) { source in
                sourceSectionCard(source)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: cardRadius))
    }

    private func sourceSectionCard(_ source: UsageSource) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            sourceSection(source)
        }
        .padding(12)
        .background(Color.primary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func sourceSection(_ source: UsageSource) -> some View {
        let stats = usageTracker.rankedStats(for: source)
        let visibleStats = Array(stats.prefix(maxDisplayedSkillsPerSource))

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(source.displayName.uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .tracking(0.5)
                Text("\(stats.count)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Color.secondary.opacity(0.12))
                    .clipShape(Capsule())
            }

            ForEach(Array(visibleStats.enumerated()), id: \.element.id) { index, stat in
                if index > 0 {
                    Divider()
                }
                rankedRow(stat: stat, index: index + 1)
            }
        }
    }

    private func rankedRow(stat: SkillUsageStat, index: Int) -> some View {
        HStack(spacing: 10) {
            Text("#\(index)")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(.tertiary)
                .frame(width: 26, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(stat.displayCommand)
                        .font(.system(size: 13, weight: .medium))
                    if !installedSkillIdentifiers.contains(stat.id) {
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

    private func sourceSummaryItem(_ source: UsageSource) -> some View {
        VStack(spacing: 4) {
            Text(source.displayName)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            Text("\(usageTracker.totalInvocations(for: source))")
                .font(.system(size: 15, weight: .bold, design: .monospaced))
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func sourceTag(_ source: UsageSource) -> some View {
        Text(source.shortLabel)
            .font(.system(size: 9, weight: .bold))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Color.secondary.opacity(0.12))
            .foregroundStyle(.secondary)
            .clipShape(Capsule())
    }

    private func relativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
