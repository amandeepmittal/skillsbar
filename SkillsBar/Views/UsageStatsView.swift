import SwiftUI

private let cardBackground = Color.primary.opacity(0.10)
private let cardRadius: CGFloat = 12
private let maxUsageRows = 10

private enum UsageStatsRange: String, CaseIterable, Identifiable {
    case thirtyDays
    case sevenDays
    case all

    var id: String { rawValue }

    var title: String {
        switch self {
        case .thirtyDays:
            return "30d"
        case .sevenDays:
            return "7d"
        case .all:
            return "All"
        }
    }

    var displayTitle: String {
        switch self {
        case .thirtyDays:
            return "Last 30 days"
        case .sevenDays:
            return "Last 7 days"
        case .all:
            return "All time"
        }
    }

    var cutoffDate: Date? {
        switch self {
        case .thirtyDays:
            return Calendar.current.date(byAdding: .day, value: -30, to: Date())
        case .sevenDays:
            return Calendar.current.date(byAdding: .day, value: -7, to: Date())
        case .all:
            return nil
        }
    }

    var dayCount: Int? {
        switch self {
        case .thirtyDays:
            return 30
        case .sevenDays:
            return 7
        case .all:
            return nil
        }
    }
}

private struct DailyUsageBucket: Identifiable {
    let date: Date
    let count: Int
    let invocations: [SkillInvocation]

    var id: Date { date }
}

private struct MonthlyUsageBucket: Identifiable {
    let monthStart: Date
    let count: Int
    let invocations: [SkillInvocation]

    var id: Date { monthStart }
}

struct UsageStatsView: View {
    @ObservedObject var usageTracker: UsageTracker
    let installedSkills: [Skill]
    let onSelectSkill: (Skill) -> Void
    let onCopyTrigger: (String) -> Void
    let onBack: () -> Void

    @State private var selectedRange: UsageStatsRange = .thirtyDays
    @State private var hoveredUsageHelp: String?
    @State private var hoveredUsageFrame: CGRect = .zero
    @State private var hoveredUsageFrames: [String: CGRect] = [:]

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if usageTracker.stats.isEmpty && !usageTracker.isLoading {
                emptyState
            } else {
                ScrollView {
                    VStack(spacing: 10) {
                        rangePicker
                        usageSummaryCard
                        heatmapCard
                        skillsCard
                    }
                    .padding(14)
                }
            }
        }
        .coordinateSpace(name: "usageStatsView")
        .overlay(alignment: .topLeading) {
            if let hoveredUsageHelp {
                Text(hoveredUsageHelp)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineSpacing(2)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 7)
                    .background(.regularMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .shadow(color: Color.black.opacity(0.18), radius: 10, y: 4)
                    .offset(x: hoveredUsageFrame.midX - 74, y: max(8, hoveredUsageFrame.minY - 76))
                    .allowsHitTesting(false)
            }
        }
        .frame(width: SkillsBarLayout.windowWidth, height: SkillsBarLayout.detailHeight)
    }

    private var header: some View {
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

            VStack(spacing: 1) {
                Text("Usage Stats")
                    .font(.system(size: 16, weight: .bold))
                Text(refreshStatusText)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

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
    }

    private var rangePicker: some View {
        Picker("Range", selection: $selectedRange) {
            ForEach(UsageStatsRange.allCases) { range in
                Text(range.title).tag(range)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    private var usageSummaryCard: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(selectedRange.displayTitle.uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .tracking(0.5)

                Text("\(selectedTotal)")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .lineLimit(1)

                Text(summaryCaption)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 8) {
                summaryMetric(value: "\(rangeStats.count)", label: "Skills")
                summaryMetric(value: "\(sourceCount)", label: sourceCount == 1 ? "Source" : "Sources")
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: cardRadius))
    }

    private func summaryMetric(value: String, label: String) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(value)
                .font(.system(size: 15, weight: .bold, design: .monospaced))
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
    }

    private var heatmapCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                sectionHeader(selectedRange == .all ? "ACTIVITY BY MONTH" : "ACTIVITY BY DAY", count: nil)
                Spacer()
                Text(heatmapCaption)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }

            if selectedRange == .all {
                monthlyHeatmap
            } else {
                dailyHeatmap
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: cardRadius))
    }

    private var dailyHeatmap: some View {
        let buckets = dailyBuckets()
        let maximum = max(1, buckets.map(\.count).max() ?? 0)
        let cellSize: CGFloat = selectedRange == .sevenDays ? 42 : 11
        let spacing: CGFloat = selectedRange == .sevenDays ? 8 : 4

        return HStack(alignment: .bottom, spacing: spacing) {
            ForEach(buckets) { bucket in
                let help = dailyBucketHelp(bucket)
                let fraction = maximum > 0 ? CGFloat(bucket.count) / CGFloat(maximum) : 0
                let barHeight = selectedRange == .sevenDays ? 12 + (46 * fraction) : cellSize
                RoundedRectangle(cornerRadius: selectedRange == .sevenDays ? 7 : 3)
                    .fill(heatmapColor(count: bucket.count, maximum: maximum))
                    .frame(width: cellSize, height: barHeight)
                    .background(usageHoverReader(help: help))
                    .onHover { isHovering in
                        if isHovering {
                            hoveredUsageHelp = help
                            hoveredUsageFrame = hoveredUsageFrames[help] ?? hoveredUsageFrame
                        } else if hoveredUsageHelp == help {
                            hoveredUsageHelp = nil
                        }
                    }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var monthlyHeatmap: some View {
        let buckets = monthlyBuckets()
        let maximum = max(1, buckets.map(\.count).max() ?? 0)

        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(buckets) { bucket in
                    let help = monthlyBucketHelp(bucket)
                    VStack(spacing: 5) {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(heatmapColor(count: bucket.count, maximum: maximum))
                            .frame(width: 30, height: 30)
                            .background(usageHoverReader(help: help))
                            .onHover { isHovering in
                                if isHovering {
                                    hoveredUsageHelp = help
                                    hoveredUsageFrame = hoveredUsageFrames[help] ?? hoveredUsageFrame
                                } else if hoveredUsageHelp == help {
                                    hoveredUsageHelp = nil
                                }
                            }

                        Text(shortMonthFormatter.string(from: bucket.monthStart))
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.tertiary)
                            .frame(width: 34)
                    }
                }
            }
        }
    }

    private var skillsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("SKILLS", count: rangeStats.count)

            if visibleStats.isEmpty {
                Text("No usage in this range.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(visibleStats.enumerated()), id: \.element.id) { index, stat in
                        if index > 0 {
                            Divider()
                        }
                        usageRow(stat: stat, rank: index + 1)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: cardRadius))
    }

    private func usageRow(stat: SkillUsageStat, rank: Int) -> some View {
        let skill = installedSkill(for: stat)

        return HStack(spacing: 10) {
            Text("#\(rank)")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(.tertiary)
                .frame(width: 28, alignment: .leading)

            sourceIcon(stat.source)

            VStack(alignment: .leading, spacing: 4) {
                Text(stat.displayCommand)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)

                Text(rowCaption(for: stat))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 5) {
                Text("\(stat.totalCount)")
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)

                HStack(spacing: 4) {
                    iconButton("Copy trigger", iconName: "doc.on.doc") {
                        onCopyTrigger(stat.displayCommand)
                    }

                    if let skill {
                        iconButton("Open skill", iconName: "arrow.forward.circle") {
                            onSelectSkill(skill)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 8)
    }

    private var refreshStatusText: String {
        if usageTracker.isLoading {
            return "Refreshing"
        }

        guard let lastRefreshDate = usageTracker.lastRefreshDate else {
            return "Not refreshed yet"
        }

        return "Updated \(relativeDate(lastRefreshDate))"
    }

    private var rangeStats: [SkillUsageStat] {
        usageTracker.rankedStats(since: selectedRange.cutoffDate)
    }

    private var visibleStats: [SkillUsageStat] {
        Array(rangeStats.prefix(maxUsageRows))
    }

    private var selectedTotal: Int {
        rangeStats.reduce(0) { $0 + $1.totalCount }
    }

    private var sourceCount: Int {
        Set(rangeStats.map(\.source)).count
    }

    private var selectedInvocations: [SkillInvocation] {
        rangeStats.flatMap(\.invocations)
    }

    private var summaryCaption: String {
        guard selectedTotal > 0 else { return "No usage recorded" }
        let uses = selectedTotal == 1 ? "use" : "uses"
        let skills = rangeStats.count == 1 ? "skill" : "skills"
        return "\(selectedTotal) \(uses), \(rangeStats.count) active \(skills)"
    }

    private var heatmapCaption: String {
        guard let first = selectedInvocations.map(\.timestamp).min(),
              let last = selectedInvocations.map(\.timestamp).max() else {
            return "No activity"
        }

        if selectedRange == .all {
            return "\(shortMonthFormatter.string(from: first))-\(shortMonthFormatter.string(from: last))"
        }

        return "\(shortDateFormatter.string(from: first))-\(shortDateFormatter.string(from: last))"
    }

    private func dailyBuckets() -> [DailyUsageBucket] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let dayCount = selectedRange.dayCount ?? 30
        let dates = stride(from: dayCount - 1, through: 0, by: -1).compactMap { offset in
            calendar.date(byAdding: .day, value: -offset, to: today)
        }
        let counts = Dictionary(grouping: selectedInvocations) { invocation in
            calendar.startOfDay(for: invocation.timestamp)
        }

        return dates.map { date in
            let invocations = counts[date, default: []]
            return DailyUsageBucket(date: date, count: invocations.count, invocations: invocations)
        }
    }

    private func monthlyBuckets() -> [MonthlyUsageBucket] {
        let calendar = Calendar.current
        let allInvocations = usageTracker.rankedStats(since: nil).flatMap(\.invocations)
        guard let firstDate = allInvocations.map(\.timestamp).min() else { return [] }

        let firstMonth = startOfMonth(for: firstDate)
        let currentMonth = startOfMonth(for: Date())
        let invocationsByMonth = Dictionary(grouping: allInvocations) { invocation in
            startOfMonth(for: invocation.timestamp)
        }

        var buckets: [MonthlyUsageBucket] = []
        var cursor = firstMonth
        while cursor <= currentMonth {
            let invocations = invocationsByMonth[cursor, default: []]
            buckets.append(MonthlyUsageBucket(monthStart: cursor, count: invocations.count, invocations: invocations))
            guard let nextMonth = calendar.date(byAdding: .month, value: 1, to: cursor) else { break }
            cursor = nextMonth
        }

        return buckets
    }

    private func startOfMonth(for date: Date) -> Date {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: components) ?? calendar.startOfDay(for: date)
    }

    private func heatmapColor(count: Int, maximum: Int) -> Color {
        guard count > 0 else {
            return Color.primary.opacity(0.08)
        }

        let fraction = min(1, max(0.18, Double(count) / Double(maximum)))
        return Color.blue.opacity(0.20 + fraction * 0.55)
    }

    private func dailyBucketHelp(_ bucket: DailyUsageBucket) -> String {
        usageHelp(
            title: fullDateFormatter.string(from: bucket.date),
            invocations: bucket.invocations
        )
    }

    private func monthlyBucketHelp(_ bucket: MonthlyUsageBucket) -> String {
        return usageHelp(
            title: monthYearFormatter.string(from: bucket.monthStart),
            invocations: bucket.invocations
        )
    }

    private func usageHelp(title: String, invocations: [SkillInvocation]) -> String {
        var lines = [
            title,
            "\(invocations.count) \(invocations.count == 1 ? "use" : "uses")",
        ]

        let sourceLines = sourceBreakdownLines(for: invocations)
        if !sourceLines.isEmpty {
            lines.append(contentsOf: sourceLines)
        }

        return lines.joined(separator: "\n")
    }

    private func sourceBreakdownLines(for invocations: [SkillInvocation]) -> [String] {
        let sourceCounts = Dictionary(grouping: invocations, by: \.source).mapValues(\.count)
        return UsageSource.allCases.compactMap { source in
            guard let count = sourceCounts[source], count > 0 else { return nil }
            return "\(source.shortLabel): \(count)"
        }
    }

    private func usageHoverReader(help: String) -> some View {
        GeometryReader { proxy in
            Color.clear
                .onAppear {
                    setUsageFrame(help: help, frame: proxy.frame(in: .named("usageStatsView")))
                }
                .onChange(of: proxy.frame(in: .named("usageStatsView"))) { _, frame in
                    setUsageFrame(help: help, frame: frame)
                }
        }
    }

    private func setUsageFrame(help: String, frame: CGRect) {
        hoveredUsageFrames[help] = frame
        if hoveredUsageHelp == help {
            hoveredUsageFrame = frame
        }
    }

    private func rowCaption(for stat: SkillUsageStat) -> String {
        if let lastUsedDate = stat.lastUsedDate {
            return "Last \(relativeDate(lastUsedDate)), \(stat.frequencyDescription)"
        }
        return stat.frequencyDescription
    }

    private func installedSkill(for stat: SkillUsageStat) -> Skill? {
        installedSkills.first { UsageTracker.identifier(for: $0) == stat.id }
    }

    private func sourceIcon(_ source: UsageSource) -> some View {
        Image(sourceAssetName(source))
            .renderingMode(.template)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .foregroundStyle(sourceTint(source))
            .frame(width: 18, height: 18)
    }

    private func sourceAssetName(_ source: UsageSource) -> String {
        switch source {
        case .claudeCode:
            return "ClaudeLogo"
        case .codexCLI:
            return "CodexLogo"
        }
    }

    private func sourceTint(_ source: UsageSource) -> Color {
        switch source {
        case .claudeCode:
            return .orange
        case .codexCLI:
            return .blue
        }
    }

    private func iconButton(_ help: String, iconName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: iconName)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 20, height: 20)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help(help)
    }

    private func sectionHeader(_ title: String, count: Int?) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .tracking(0.5)

            if let count {
                Text("\(count)")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Color.secondary.opacity(0.12))
                    .clipShape(Capsule())
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "chart.bar")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text("No Usage Data")
                .font(.system(size: 16, weight: .semibold))
            Text("Usage appears here after SkillsBar sees Claude Code or Codex skill activity.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func relativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private var shortDateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMM d")
        return formatter
    }

    private var fullDateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }

    private var shortMonthFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMM")
        return formatter
    }

    private var monthYearFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMM y")
        return formatter
    }
}
