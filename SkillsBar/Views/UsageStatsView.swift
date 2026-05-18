import SwiftUI

private let cardBackground = Color.primary.opacity(0.10)
private let cardRadius: CGFloat = 12
private let maxCollapsedUsageRows = 12

private enum UsageStatsFilter: String, CaseIterable, Identifiable {
    case all
    case recent
    case stale
    case unused
    case missing
    case project
    case claudeCode
    case codexCLI

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            return "All"
        case .recent:
            return "Recent"
        case .stale:
            return "Stale"
        case .unused:
            return "Unused"
        case .missing:
            return "Missing"
        case .project:
            return "Project"
        case .claudeCode:
            return "Claude"
        case .codexCLI:
            return "Codex"
        }
    }

    var iconName: String {
        switch self {
        case .all:
            return "chart.bar"
        case .recent:
            return "clock"
        case .stale:
            return "exclamationmark.triangle"
        case .unused:
            return "tray"
        case .missing:
            return "externaldrive.badge.exclamationmark"
        case .project:
            return "folder"
        case .claudeCode:
            return "ClaudeLogo"
        case .codexCLI:
            return "CodexLogo"
        }
    }

    var source: UsageSource? {
        switch self {
        case .claudeCode:
            return .claudeCode
        case .codexCLI:
            return .codexCLI
        default:
            return nil
        }
    }
}

private struct ProjectUsageRollup: Identifiable {
    let projectName: String
    let projectPath: String
    let confirmedCount: Int
    let matchedSkillCount: Int
    let topCommands: [String]

    var id: String { projectPath }
}

private enum UsageAvailabilityStatus: Equatable {
    case available
    case missingOnDisk
    case notInstalled

    var label: String {
        switch self {
        case .available:
            return ""
        case .missingOnDisk:
            return "missing on disk"
        case .notInstalled:
            return "not installed"
        }
    }

    var iconName: String {
        switch self {
        case .available:
            return ""
        case .missingOnDisk:
            return "externaldrive.badge.exclamationmark"
        case .notInstalled:
            return "arrow.down.circle"
        }
    }

    var tint: Color {
        switch self {
        case .available:
            return .secondary
        case .missingOnDisk:
            return Color(red: 0.76, green: 0.20, blue: 0.25)
        case .notInstalled:
            return Color(red: 0.21, green: 0.42, blue: 0.78)
        }
    }

    var isUnavailable: Bool {
        self != .available
    }
}

struct UsageStatsView: View {
    @ObservedObject var usageTracker: UsageTracker
    let installedSkills: [Skill]
    let installedSkillIdentifiers: Set<String>
    let projectUsageContextsByIdentifier: [String: [ProjectSkillUsageContext]]
    let onSelectSkill: (Skill) -> Void
    let onCopyTrigger: (String) -> Void
    let onBack: () -> Void

    @State private var selectedFilter: UsageStatsFilter = .all
    @State private var showAllUsageRows = false

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

            Divider()

            if usageTracker.stats.isEmpty && !usageTracker.isLoading {
                emptyState
            } else {
                ScrollView {
                    VStack(spacing: 10) {
                        usageOverviewCard
                        actionInsightsCard
                        usageFilterBar
                        usageListCard
                        projectUsageCard
                    }
                    .padding(14)
                }
            }
        }
        .frame(width: SkillsBarLayout.windowWidth, height: SkillsBarLayout.detailHeight)
    }

    // MARK: - Overview

    private var refreshStatusText: String {
        if usageTracker.isLoading {
            return "Refreshing"
        }

        guard let lastRefreshDate = usageTracker.lastRefreshDate else {
            return "Not refreshed yet"
        }

        return "Updated \(relativeDate(lastRefreshDate))"
    }

    private var usageOverviewCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("LAST 30 DAYS")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .tracking(0.5)
                    Text("\(usageCount(days: 30))")
                        .font(.system(size: 32, weight: .bold, design: .monospaced))
                        .lineLimit(1)
                    Text("\(usageCount(days: 7)) this week, \(usageTracker.stats.count) tracked skills")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                if let topSource {
                    VStack(alignment: .trailing, spacing: 6) {
                        sourceTag(topSource)
                        Text("\(usageTracker.totalInvocations(for: topSource)) uses")
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            HStack(spacing: 8) {
                overviewMetric(value: "\(usageTracker.totalInvocations)", label: "Total")
                overviewMetric(value: "\(activeStats(days: 30).count)", label: "Active")
                overviewMetric(value: "\(neverUsedSkills.count)", label: "Unused")
                overviewMetric(value: "\(missingStats.count)", label: "Missing")
            }

            if usageTracker.sourcesWithStats.count > 1 {
                sourceSplitView
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: cardRadius))
    }

    private var topSource: UsageSource? {
        usageTracker.sourcesWithStats.max {
            usageTracker.totalInvocations(for: $0) < usageTracker.totalInvocations(for: $1)
        }
    }

    private func overviewMetric(value: String, label: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .monospaced))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 9))
    }

    private var sourceSplitView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("SOURCE SPLIT")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .tracking(0.5)
                Spacer()
                Text(dateRange)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }

            GeometryReader { proxy in
                let total = max(1, usageTracker.totalInvocations)
                let spacing: CGFloat = 4
                let availableWidth = max(0, proxy.size.width - CGFloat(max(0, usageTracker.sourcesWithStats.count - 1)) * spacing)
                HStack(spacing: spacing) {
                    ForEach(usageTracker.sourcesWithStats, id: \.self) { source in
                        let fraction = Double(usageTracker.totalInvocations(for: source)) / Double(total)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(sourceTint(source).opacity(0.55))
                            .frame(width: max(6, availableWidth * fraction))
                    }
                }
            }
            .frame(height: 6)

            HStack(spacing: 8) {
                ForEach(usageTracker.sourcesWithStats, id: \.self) { source in
                    HStack(spacing: 4) {
                        Circle()
                            .fill(sourceTint(source).opacity(0.75))
                            .frame(width: 6, height: 6)
                        Text("\(source.displayName) \(usageTracker.totalInvocations(for: source))")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: - Action Insights

    private var actionInsightsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            statsSectionHeader("INSIGHTS", count: nil)

            if let top = usageTracker.mostUsed {
                actionableInsightRow(
                    icon: "crown.fill",
                    color: .yellow,
                    label: "Most used",
                    value: "\(top.displayCommand) (\(top.totalCount)x)",
                    actionTitle: installedSkill(for: top) == nil ? "Copy" : "Open",
                    action: {
                        if let skill = installedSkill(for: top) {
                            onSelectSkill(skill)
                        } else {
                            onCopyTrigger(top.displayCommand)
                        }
                    }
                )
            }

            if let latest = latestUsedStat {
                actionableInsightRow(
                    icon: "clock.fill",
                    color: .blue,
                    label: "Last used",
                    value: "\(latest.displayCommand) \(relativeDate(latest.lastUsedDate ?? Date()))",
                    actionTitle: "Recent",
                    action: { selectFilter(.recent) }
                )
            }

            if !neverUsedSkills.isEmpty {
                actionableInsightRow(
                    icon: "tray.fill",
                    color: .orange,
                    label: "Unused",
                    value: "\(neverUsedSkills.count) installed skills have no usage yet",
                    actionTitle: "Review",
                    action: { selectFilter(.unused) }
                )
            }

            if !missingStats.isEmpty {
                actionableInsightRow(
                    icon: "externaldrive.badge.exclamationmark",
                    color: Color(red: 0.76, green: 0.20, blue: 0.25),
                    label: "History only",
                    value: "\(missingStats.count) used skills are not installed now",
                    actionTitle: "Show",
                    action: { selectFilter(.missing) }
                )
            } else if usageTracker.staleSkills.isEmpty && neverUsedSkills.isEmpty {
                Text("Your tracked skills are installed and recently active.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            if !usageTracker.staleSkills.isEmpty {
                actionableInsightRow(
                    icon: "exclamationmark.triangle.fill",
                    color: .orange,
                    label: "Stale",
                    value: "\(usageTracker.staleSkills.count) skills have been quiet for 30 days",
                    actionTitle: "Show",
                    action: { selectFilter(.stale) }
                )
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: cardRadius))
    }

    private var latestUsedStat: SkillUsageStat? {
        usageTracker.rankedStats.compactMap { stat -> (SkillUsageStat, Date)? in
            guard let lastUsedDate = stat.lastUsedDate else { return nil }
            return (stat, lastUsedDate)
        }
        .max(by: { $0.1 < $1.1 })?
        .0
    }

    private func actionableInsightRow(
        icon: String,
        color: Color,
        label: String,
        value: String,
        actionTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer(minLength: 8)

            Button(actionTitle, action: action)
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.blue)
                .lineLimit(1)
        }
        .padding(8)
        .background(Color.primary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 9))
    }

    // MARK: - Filtered List

    private var usageFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(UsageStatsFilter.allCases) { filter in
                    filterChip(filter)
                }
            }
        }
    }

    private func filterChip(_ filter: UsageStatsFilter) -> some View {
        Button {
            selectFilter(filter)
        } label: {
            HStack(spacing: 5) {
                filterIcon(filter)
                Text(filter.title)
                    .font(.system(size: 11, weight: .semibold))
                Text("\(filterCount(filter))")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(selectedFilter == filter ? .white.opacity(0.85) : .secondary)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(selectedFilter == filter ? Color.blue : Color.primary.opacity(0.08))
            .foregroundStyle(selectedFilter == filter ? .white : .secondary)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var usageListCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                statsSectionHeader(listTitle, count: selectedFilter == .unused ? neverUsedSkills.count : filteredStats.count)

                Spacer()

                if canToggleUsageRows {
                    Button(showAllUsageRows ? "Show Fewer" : "Show All") {
                        showAllUsageRows.toggle()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.blue)
                }
            }

            if selectedFilter == .unused {
                unusedSkillsList
            } else {
                filteredStatsList
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: cardRadius))
    }

    private var filteredStatsList: some View {
        VStack(spacing: 0) {
            if visibleStats.isEmpty {
                compactEmptyState("No matching usage yet.")
            } else {
                ForEach(Array(visibleStats.enumerated()), id: \.element.id) { index, stat in
                    if index > 0 {
                        Divider()
                    }
                    usageStatRow(stat: stat, index: index + 1)
                }
            }
        }
    }

    private var unusedSkillsList: some View {
        VStack(spacing: 0) {
            if visibleUnusedSkills.isEmpty {
                compactEmptyState("Every installed skill has usage history.")
            } else {
                ForEach(Array(visibleUnusedSkills.enumerated()), id: \.element.id) { index, skill in
                    if index > 0 {
                        Divider()
                    }
                    unusedSkillRow(skill, index: index + 1)
                }
            }
        }
    }

    private var listTitle: String {
        switch selectedFilter {
        case .all:
            return "TOP SKILLS"
        case .recent:
            return "RECENTLY USED"
        case .stale:
            return "STALE SKILLS"
        case .unused:
            return "UNUSED INSTALLED"
        case .missing:
            return "HISTORY ONLY"
        case .project:
            return "PROJECT USAGE"
        case .claudeCode:
            return "CLAUDE CODE"
        case .codexCLI:
            return "CODEX"
        }
    }

    private var filteredStats: [SkillUsageStat] {
        switch selectedFilter {
        case .all:
            return usageTracker.rankedStats
        case .recent:
            return recentlyUsedStats
        case .stale:
            return usageTracker.staleSkills
        case .unused:
            return []
        case .missing:
            return missingStats
        case .project:
            return statsWithProjectContexts
        case .claudeCode:
            return usageTracker.rankedStats(for: .claudeCode)
        case .codexCLI:
            return usageTracker.rankedStats(for: .codexCLI)
        }
    }

    private var visibleStats: [SkillUsageStat] {
        Array(filteredStats.prefix(showAllUsageRows ? filteredStats.count : maxCollapsedUsageRows))
    }

    private var visibleUnusedSkills: [Skill] {
        Array(neverUsedSkills.prefix(showAllUsageRows ? neverUsedSkills.count : maxCollapsedUsageRows))
    }

    private var canToggleUsageRows: Bool {
        let count = selectedFilter == .unused ? neverUsedSkills.count : filteredStats.count
        return count > maxCollapsedUsageRows
    }

    private func usageStatRow(stat: SkillUsageStat, index: Int) -> some View {
        let availability = availabilityStatus(for: stat)
        let projectContexts = projectUsageContexts(for: stat)
        let skill = installedSkill(for: stat)

        return HStack(spacing: 10) {
            Text("#\(index)")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(.tertiary)
                .frame(width: 28, alignment: .leading)

            sourceIcon(stat.source)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(stat.displayCommand)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(availability.isUnavailable ? .secondary : .primary)
                        .lineLimit(1)

                    if availability.isUnavailable {
                        availabilityBadge(availability)
                    }

                    if !projectContexts.isEmpty {
                        projectUsageBadges(for: projectContexts)
                    }
                }

                HStack(spacing: 6) {
                    if let lastUsed = stat.lastUsedDate {
                        Text("Last \(relativeDate(lastUsed))")
                    }
                    Text(stat.frequencyDescription)
                    if availability.isUnavailable {
                        Text("History only")
                            .foregroundStyle(availability.tint)
                    }
                }
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .lineLimit(1)

                usageBar(stat: stat)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 6) {
                Text("\(stat.totalCount)x")
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(availability.isUnavailable ? .tertiary : .secondary)

                HStack(spacing: 4) {
                    usageIconButton("Copy trigger", iconName: "doc.on.doc") {
                        onCopyTrigger(stat.displayCommand)
                    }

                    if let skill {
                        usageIconButton("Open skill", iconName: "arrow.forward.circle") {
                            onSelectSkill(skill)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 8)
    }

    private func unusedSkillRow(_ skill: Skill, index: Int) -> some View {
        let source = UsageTracker.source(for: skill.source)

        return HStack(spacing: 10) {
            Text("#\(index)")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(.tertiary)
                .frame(width: 28, alignment: .leading)

            sourceAssetIcon(source, size: 14)
                .foregroundStyle(sourceTint(source))
                .frame(width: 18, height: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(skill.displayName)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                Text("\(skill.triggerCommand) | \(skill.source.shortScopeLabel)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            HStack(spacing: 4) {
                usageIconButton("Copy trigger", iconName: "doc.on.doc") {
                    onCopyTrigger(skill.triggerCommand)
                }

                usageIconButton("Open skill", iconName: "arrow.forward.circle") {
                    onSelectSkill(skill)
                }
            }
        }
        .padding(.vertical, 8)
    }

    private func usageBar(stat: SkillUsageStat) -> some View {
        let maximum = max(1, usageTracker.rankedStats.first?.totalCount ?? stat.totalCount)
        let fraction = max(0.04, min(1, Double(stat.totalCount) / Double(maximum)))

        return ZStack(alignment: .leading) {
            Capsule()
                .fill(Color.primary.opacity(0.08))
            Capsule()
                .fill(sourceTint(stat.source).opacity(0.55))
                .frame(width: 86 * fraction)
        }
        .frame(width: 86, height: 4)
    }

    private func usageIconButton(_ help: String, iconName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: iconName)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 20, height: 20)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help(help)
    }

    private func compactEmptyState(_ message: String) -> some View {
        Text(message)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
    }

    // MARK: - Project Usage

    @ViewBuilder
    private var projectUsageCard: some View {
        if !projectRollups.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                statsSectionHeader("BY PROJECT", count: projectRollups.count)

                ForEach(Array(projectRollups.prefix(5).enumerated()), id: \.element.id) { index, rollup in
                    if index > 0 {
                        Divider()
                    }
                    projectRollupRow(rollup)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: cardRadius))
        }
    }

    private var projectRollups: [ProjectUsageRollup] {
        var buckets: [String: (projectName: String, projectPath: String, confirmedCount: Int, matchedSkillCount: Int, commands: [String: Int])] = [:]

        for (identifier, contexts) in projectUsageContextsByIdentifier {
            let stat = usageTracker.stats[identifier]

            for context in contexts {
                var bucket = buckets[context.projectPath] ?? (
                    projectName: context.projectName,
                    projectPath: context.projectPath,
                    confirmedCount: 0,
                    matchedSkillCount: 0,
                    commands: [:]
                )

                bucket.confirmedCount += context.confirmedCount
                bucket.matchedSkillCount += 1

                if let stat {
                    bucket.commands[stat.displayCommand, default: 0] += max(1, context.confirmedCount)
                }

                buckets[context.projectPath] = bucket
            }
        }

        return buckets.values.map { bucket in
            let topCommands = bucket.commands
                .sorted { lhs, rhs in
                    if lhs.value != rhs.value {
                        return lhs.value > rhs.value
                    }
                    return lhs.key.localizedCaseInsensitiveCompare(rhs.key) == .orderedAscending
                }
                .prefix(3)
                .map(\.key)

            return ProjectUsageRollup(
                projectName: bucket.projectName,
                projectPath: bucket.projectPath,
                confirmedCount: bucket.confirmedCount,
                matchedSkillCount: bucket.matchedSkillCount,
                topCommands: Array(topCommands)
            )
        }
        .sorted { lhs, rhs in
            if lhs.confirmedCount != rhs.confirmedCount {
                return lhs.confirmedCount > rhs.confirmedCount
            }
            if lhs.matchedSkillCount != rhs.matchedSkillCount {
                return lhs.matchedSkillCount > rhs.matchedSkillCount
            }
            return lhs.projectName.localizedCaseInsensitiveCompare(rhs.projectName) == .orderedAscending
        }
    }

    private func projectRollupRow(_ rollup: ProjectUsageRollup) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "folder")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.blue)
                .frame(width: 18, height: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(rollup.projectName)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                Text(rollup.topCommands.isEmpty ? rollup.projectPath : rollup.topCommands.joined(separator: ", "))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 2) {
                Text(rollup.confirmedCount > 0 ? "\(rollup.confirmedCount)x" : "Installed")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(rollup.confirmedCount > 0 ? .primary : .secondary)
                Text("\(rollup.matchedSkillCount) skills")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 7)
    }

    // MARK: - Derived Values

    private var missingStats: [SkillUsageStat] {
        usageTracker.rankedStats.filter { availabilityStatus(for: $0).isUnavailable }
    }

    private var statsWithProjectContexts: [SkillUsageStat] {
        usageTracker.rankedStats
            .filter { !projectUsageContexts(for: $0).isEmpty }
            .sorted { lhs, rhs in
                let lhsCount = projectUsageContexts(for: lhs).reduce(0) { $0 + $1.confirmedCount }
                let rhsCount = projectUsageContexts(for: rhs).reduce(0) { $0 + $1.confirmedCount }
                if lhsCount != rhsCount {
                    return lhsCount > rhsCount
                }
                return lhs.totalCount > rhs.totalCount
            }
    }

    private func activeStats(days: Int) -> [SkillUsageStat] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        return usageTracker.rankedStats.filter { ($0.lastUsedDate ?? .distantPast) >= cutoff }
    }

    private func filterCount(_ filter: UsageStatsFilter) -> Int {
        switch filter {
        case .all:
            return usageTracker.rankedStats.count
        case .recent:
            return recentlyUsedStats.count
        case .stale:
            return usageTracker.staleSkills.count
        case .unused:
            return neverUsedSkills.count
        case .missing:
            return missingStats.count
        case .project:
            return statsWithProjectContexts.count
        case .claudeCode:
            return usageTracker.skillCount(for: .claudeCode)
        case .codexCLI:
            return usageTracker.skillCount(for: .codexCLI)
        }
    }

    private func selectFilter(_ filter: UsageStatsFilter) {
        selectedFilter = filter
        showAllUsageRows = false
    }

    private func installedSkill(for stat: SkillUsageStat) -> Skill? {
        installedSkills.first { UsageTracker.identifier(for: $0) == stat.id }
    }

    private func statsSectionHeader(_ title: String, count: Int?) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .tracking(0.5)
            if let count {
                Text("\(count)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Color.secondary.opacity(0.12))
                    .clipShape(Capsule())
            }
        }
    }

    private func sourceIcon(_ source: UsageSource) -> some View {
        sourceAssetIcon(source, size: 14)
            .foregroundStyle(sourceTint(source))
            .frame(width: 18, height: 18)
    }

    @ViewBuilder
    private func filterIcon(_ filter: UsageStatsFilter) -> some View {
        if let source = filter.source {
            sourceAssetIcon(source, size: 12)
        } else {
            Image(systemName: filter.iconName)
                .font(.system(size: 10, weight: .semibold))
        }
    }

    private func sourceAssetIcon(_ source: UsageSource, size: CGFloat) -> some View {
        Image(sourceAssetName(source))
            .renderingMode(.template)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
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

    private var allInvocations: [SkillInvocation] {
        usageTracker.stats.values.flatMap(\.invocations)
    }

    private func usageCount(days: Int) -> Int {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        return allInvocations.filter { $0.timestamp >= cutoff }.count
    }

    private var recentlyUsedStats: [SkillUsageStat] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        return usageTracker.rankedStats
            .filter { ($0.lastUsedDate ?? .distantPast) >= cutoff }
            .sorted { ($0.lastUsedDate ?? .distantPast) > ($1.lastUsedDate ?? .distantPast) }
    }

    private var neverUsedSkills: [Skill] {
        installedSkills.filter { usageTracker.stat(for: $0) == nil }
    }

    // MARK: - Helpers

    private func sourceTag(_ source: UsageSource) -> some View {
        Text(source.shortLabel)
            .font(.system(size: 9, weight: .bold))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Color.secondary.opacity(0.12))
            .foregroundStyle(.secondary)
            .clipShape(Capsule())
    }

    private func availabilityBadge(_ availability: UsageAvailabilityStatus) -> some View {
        Label(availability.label, systemImage: availability.iconName)
            .font(.system(size: 9, weight: .bold))
            .labelStyle(.titleAndIcon)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(availability.tint.opacity(0.14))
            .foregroundStyle(availability.tint)
            .clipShape(Capsule())
    }

    private func projectUsageBadges(for contexts: [ProjectSkillUsageContext]) -> some View {
        HStack(spacing: 4) {
            projectUsageBadge("Project")
            projectUsageBadge(projectUsageLabel(for: contexts), secondary: true)
        }
        .help(projectUsageHelp(for: contexts))
    }

    private func projectUsageBadge(_ label: String, secondary: Bool = false) -> some View {
        Text(label)
            .font(.system(size: 9, weight: .bold))
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color.blue.opacity(secondary ? 0.10 : 0.14))
            .foregroundStyle(.blue)
            .clipShape(Capsule())
    }

    private func projectUsageLabel(for contexts: [ProjectSkillUsageContext]) -> String {
        let confirmed = contexts.filter(\.isConfirmed)

        if confirmed.count == 1 {
            let context = confirmed[0]
            return context.confirmedCount > 0 ? "\(context.projectName) \(context.confirmedCount)x" : context.projectName
        }

        if confirmed.count > 1 {
            return "\(confirmed.count) projects"
        }

        if contexts.count == 1 {
            return contexts[0].projectName
        }

        return "\(contexts.count) projects"
    }

    private func projectUsageHelp(for contexts: [ProjectSkillUsageContext]) -> String {
        let confirmed = contexts.filter(\.isConfirmed)
        let installedOnly = contexts.filter { !$0.isConfirmed }

        var lines: [String] = []

        if !confirmed.isEmpty {
            let summary = confirmed
                .map { "\($0.projectName): \($0.confirmedCount)x" }
                .joined(separator: ", ")
            lines.append("Confirmed session project usage: \(summary).")
        }

        if !installedOnly.isEmpty {
            let projectList = installedOnly.map(\.projectName).joined(separator: ", ")
            lines.append("Installed project skill with this trigger: \(projectList).")
        }

        lines.append("Totals are still grouped by trigger, so matching global skills can share this count.")
        return lines.joined(separator: "\n")
    }

    private func projectUsageContexts(for stat: SkillUsageStat) -> [ProjectSkillUsageContext] {
        projectUsageContextsByIdentifier[stat.id] ?? []
    }

    private func availabilityStatus(for stat: SkillUsageStat) -> UsageAvailabilityStatus {
        guard !installedSkillIdentifiers.contains(stat.id) else {
            return .available
        }

        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let libraryPath: String

        switch stat.source {
        case .claudeCode:
            libraryPath = stat.skillName.contains(":")
                ? "\(home)/.claude/plugins/cache"
                : "\(home)/.claude/skills"
        case .codexCLI:
            libraryPath = stat.skillName.contains(":")
                ? "\(home)/.codex/plugins/cache"
                : "\(home)/.codex/skills"
        }

        if FileManager.default.fileExists(atPath: libraryPath) {
            return .missingOnDisk
        }

        return .notInstalled
    }

    private func relativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
