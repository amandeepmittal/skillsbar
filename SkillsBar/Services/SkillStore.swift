import Foundation
import CryptoKit
import SwiftUI

private struct SkillSearchQuery {
    let rawValue: String
    let freeText: String
    let terms: [String]
    let sourceCategories: Set<SkillSourceCategory>
    let projectTerms: [String]

    var isEmpty: Bool {
        rawValue.isEmpty
    }

    var hasFilters: Bool {
        !sourceCategories.isEmpty || !projectTerms.isEmpty
    }
}

@MainActor
final class SkillStore: ObservableObject {
    @Published var groups: [SkillGroup] = []
    @Published var agentGroups: [AgentGroup] = []
    @Published var plugins: [Plugin] = []
    @Published var collections: [SkillCollection] = []
    @Published var projectSkillRoots: [ProjectSkillRoot] = []
    @Published var lastRefreshDate: Date?
    @Published var isRefreshing = false
    @Published var searchText: String = ""
    @Published var pinnedPaths: Set<String> = []
    @Published var pinnedOrder: [String] = []
    @Published var projectPinnedSkillPaths: [String: [String]] = [:]
    @Published var sortOption: SkillSortOption = .nameAsc {
        didSet {
            guard sortOption != oldValue else { return }
            UserDefaults.standard.set(sortOption.rawValue, forKey: Self.sortKey)
            refreshGroups()
        }
    }

    private var watcher: FSEventsWatcher?
    private var watchedRefreshTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var pendingRefresh = false
    private var watchedRefreshPrefixes: [String] = []
    private var watchedCreationMarkers: Set<String> = []
    private var lastScannedSkills: [Skill] = []
    private var lastScannedAgents: [Agent] = []
    private(set) var usageTracker: UsageTracker?

    private static let pinnedKey = "pinnedSkillPaths"
    private static let pinnedOrderKey = "pinnedSkillOrder"
    private static let projectPinnedSkillPathsKey = "projectPinnedSkillPaths"
    private static let sortKey = "skillSortOption"
    private static let collectionsKey = "skillCollections"
    private static let projectSkillRootsKey = "projectSkillRoots"
    private static let watchedRefreshDelay: UInt64 = 1_500_000_000

    init(usageTracker: UsageTracker? = nil) {
        self.usageTracker = usageTracker
        if let raw = UserDefaults.standard.string(forKey: Self.sortKey),
           let saved = SkillSortOption(rawValue: raw) {
            self._sortOption = Published(initialValue: saved)
        }
        if let saved = UserDefaults.standard.stringArray(forKey: Self.pinnedKey) {
            pinnedPaths = Set(saved)
        }

        // Load or migrate pinned order
        if let savedOrder = UserDefaults.standard.stringArray(forKey: Self.pinnedOrderKey) {
            pinnedOrder = savedOrder.filter { pinnedPaths.contains($0) }
            let orderSet = Set(pinnedOrder)
            for path in pinnedPaths where !orderSet.contains(path) {
                pinnedOrder.append(path)
            }
        } else {
            pinnedOrder = Array(pinnedPaths).sorted()
        }

        if let savedData = UserDefaults.standard.data(forKey: Self.projectPinnedSkillPathsKey),
           let savedProjectPins = try? JSONDecoder().decode([String: [String]].self, from: savedData) {
            projectPinnedSkillPaths = savedProjectPins
        }

        if let savedData = UserDefaults.standard.data(forKey: Self.collectionsKey),
           let savedCollections = try? JSONDecoder().decode([SkillCollection].self, from: savedData) {
            collections = savedCollections
        }

        if let savedData = UserDefaults.standard.data(forKey: Self.projectSkillRootsKey),
           let savedRoots = try? JSONDecoder().decode([ProjectSkillRoot].self, from: savedData) {
            projectSkillRoots = savedRoots
        }
    }

    private func persistPins() {
        UserDefaults.standard.set(Array(pinnedPaths), forKey: Self.pinnedKey)
        UserDefaults.standard.set(pinnedOrder, forKey: Self.pinnedOrderKey)
    }

    private func persistProjectPins() {
        let encoded = try? JSONEncoder().encode(projectPinnedSkillPaths)
        UserDefaults.standard.set(encoded, forKey: Self.projectPinnedSkillPathsKey)
    }

    private func persistCollections() {
        let encoded = try? JSONEncoder().encode(collections)
        UserDefaults.standard.set(encoded, forKey: Self.collectionsKey)
    }

    private func persistProjectSkillRoots() {
        let encoded = try? JSONEncoder().encode(projectSkillRoots)
        UserDefaults.standard.set(encoded, forKey: Self.projectSkillRootsKey)
    }

    var orderedCollections: [SkillCollection] {
        collections.enumerated()
            .sorted { lhs, rhs in
                if lhs.element.isPinned != rhs.element.isPinned {
                    return lhs.element.isPinned && !rhs.element.isPinned
                }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }

    var orderedProjectSkillRoots: [ProjectSkillRoot] {
        projectSkillRoots.enumerated()
            .sorted { lhs, rhs in
                if lhs.element.isPinned != rhs.element.isPinned {
                    return lhs.element.isPinned && !rhs.element.isPinned
                }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }

    var enabledProjectSkillRoots: [ProjectSkillRoot] {
        orderedProjectSkillRoots.filter(\.isEnabled)
    }

    var unavailableProjectSkillRoots: [ProjectSkillRoot] {
        orderedProjectSkillRoots.filter { projectSkillRootStatus(for: $0).isUnavailable }
    }

    // MARK: - Project Skills

    func addProjectSkillRoot(_ root: ProjectSkillRoot) {
        var standardizedRoot = ProjectSkillRoot(
            name: root.name,
            path: root.path,
            isEnabled: true,
            isPinned: root.isPinned,
            trustedContentSignature: root.trustedContentSignature
        )
        if standardizedRoot.trustedContentSignature == nil {
            standardizedRoot.trustedContentSignature = projectContentSignature(for: standardizedRoot)
        }

        if let index = projectSkillRoots.firstIndex(where: { standardizedPath($0.path) == standardizedRoot.path }) {
            projectSkillRoots[index].name = standardizedRoot.name
            projectSkillRoots[index].isEnabled = true
            if projectSkillRoots[index].trustedContentSignature == nil {
                projectSkillRoots[index].trustedContentSignature = standardizedRoot.trustedContentSignature
            }
            projectSkillRoots[index].updatedAt = Date()
        } else {
            projectSkillRoots.append(standardizedRoot)
        }

        persistProjectSkillRoots()
        refresh()
        startWatching()
    }

    func renameProjectSkillRoot(_ root: ProjectSkillRoot, to name: String) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty,
              let index = projectSkillRoots.firstIndex(where: { $0.id == root.id }) else {
            return
        }

        projectSkillRoots[index].name = trimmedName
        projectSkillRoots[index].updatedAt = Date()
        persistProjectSkillRoots()
        refresh()
    }

    func setProjectSkillRoot(_ root: ProjectSkillRoot, isEnabled: Bool) {
        guard let index = projectSkillRoots.firstIndex(where: { $0.id == root.id }) else { return }
        projectSkillRoots[index].isEnabled = isEnabled
        projectSkillRoots[index].updatedAt = Date()
        persistProjectSkillRoots()
        refresh()
        startWatching()
    }

    func togglePinProjectSkillRoot(_ root: ProjectSkillRoot) {
        guard let index = projectSkillRoots.firstIndex(where: { $0.id == root.id }) else { return }
        projectSkillRoots[index].isPinned.toggle()
        projectSkillRoots[index].updatedAt = Date()
        persistProjectSkillRoots()
    }

    func moveProjectSkillRoot(from sourceID: UUID, before targetID: UUID) {
        guard sourceID != targetID,
              let sourceIndex = projectSkillRoots.firstIndex(where: { $0.id == sourceID }),
              let targetIndex = projectSkillRoots.firstIndex(where: { $0.id == targetID }) else {
            return
        }

        let movedRoot = projectSkillRoots.remove(at: sourceIndex)
        let adjustedTargetIndex = sourceIndex < targetIndex ? targetIndex - 1 : targetIndex
        projectSkillRoots.insert(movedRoot, at: adjustedTargetIndex)
        if let index = projectSkillRoots.firstIndex(where: { $0.id == sourceID }) {
            projectSkillRoots[index].updatedAt = Date()
        }
        persistProjectSkillRoots()
    }

    func canMoveProjectSkillRoot(_ root: ProjectSkillRoot, by offset: Int) -> Bool {
        let ordered = orderedProjectSkillRoots.filter { $0.isPinned == root.isPinned }
        guard let sourcePosition = ordered.firstIndex(where: { $0.id == root.id }) else { return false }
        return ordered.indices.contains(sourcePosition + offset)
    }

    func moveProjectSkillRoot(from sourceID: UUID, after targetID: UUID) {
        guard sourceID != targetID,
              let sourceIndex = projectSkillRoots.firstIndex(where: { $0.id == sourceID }),
              let targetIndex = projectSkillRoots.firstIndex(where: { $0.id == targetID }) else {
            return
        }

        let movedRoot = projectSkillRoots.remove(at: sourceIndex)
        let adjustedTargetIndex = sourceIndex < targetIndex ? targetIndex : targetIndex + 1
        projectSkillRoots.insert(movedRoot, at: min(adjustedTargetIndex, projectSkillRoots.count))
        if let index = projectSkillRoots.firstIndex(where: { $0.id == sourceID }) {
            projectSkillRoots[index].updatedAt = Date()
        }
        persistProjectSkillRoots()
    }

    func moveProjectSkillRoot(_ root: ProjectSkillRoot, by offset: Int) {
        let ordered = orderedProjectSkillRoots.filter { $0.isPinned == root.isPinned }
        guard let sourcePosition = ordered.firstIndex(where: { $0.id == root.id }) else { return }
        let destinationPosition = sourcePosition + offset
        guard ordered.indices.contains(destinationPosition) else { return }
        if offset < 0 {
            moveProjectSkillRoot(from: root.id, before: ordered[destinationPosition].id)
        } else {
            moveProjectSkillRoot(from: root.id, after: ordered[destinationPosition].id)
        }
    }

    func removeProjectSkillRoot(_ root: ProjectSkillRoot) {
        projectSkillRoots.removeAll { $0.id == root.id }
        removeSkillReferences(inside: root.claudeSkillsPath)
        removeAgentReferences(inside: root.claudeAgentsPath)
        projectPinnedSkillPaths.removeValue(forKey: root.id.uuidString)
        persistProjectPins()
        persistProjectSkillRoots()
        refresh()
        startWatching()
    }

    func projectSkillCount(for root: ProjectSkillRoot) -> Int {
        projectSkills(for: root).count
    }

    func projectSkills(for root: ProjectSkillRoot) -> [Skill] {
        lastScannedSkills.filter { skill in
            guard let projectRootPath = skill.source.projectRootPath else { return false }
            return standardizedPath(projectRootPath) == standardizedPath(root.path)
        }
    }

    func isProjectPinned(_ skill: Skill, in root: ProjectSkillRoot) -> Bool {
        projectPinnedSkillPaths[root.id.uuidString, default: []].contains(skill.path)
    }

    func toggleProjectPin(_ skill: Skill, in root: ProjectSkillRoot) {
        let key = root.id.uuidString
        var paths = projectPinnedSkillPaths[key, default: []]

        if let index = paths.firstIndex(of: skill.path) {
            paths.remove(at: index)
        } else {
            paths.append(skill.path)
        }

        if paths.isEmpty {
            projectPinnedSkillPaths.removeValue(forKey: key)
        } else {
            projectPinnedSkillPaths[key] = paths
        }

        persistProjectPins()
    }

    func projectSortedSkills(for root: ProjectSkillRoot, skills: [Skill]? = nil) -> [Skill] {
        let source = skills ?? projectSkills(for: root)
        let projectPinnedOrder = projectPinnedSkillPaths[root.id.uuidString, default: []]
        guard !projectPinnedOrder.isEmpty else { return sortSkills(source) }

        let lookup = Dictionary(source.map { ($0.path, $0) }, uniquingKeysWith: { first, _ in first })
        let pinned = projectPinnedOrder.compactMap { lookup[$0] }
        let pinnedPaths = Set(pinned.map(\.path))
        let remaining = sortSkills(source.filter { !pinnedPaths.contains($0.path) })
        return pinned + remaining
    }

    func projectAgents(for root: ProjectSkillRoot) -> [Agent] {
        lastScannedAgents.filter { agent in
            guard let projectRootPath = agent.source.projectRootPath else { return false }
            return standardizedPath(projectRootPath) == standardizedPath(root.path)
        }
    }

    func projectInstructions(for root: ProjectSkillRoot) -> [ProjectInstructionFile] {
        ProjectInstructionKind.allCases.compactMap { kind in
            let path = (root.path as NSString).appendingPathComponent(kind.relativePath)
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
                  !isDirectory.boolValue else {
                return nil
            }

            let lastModified = (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date
            return ProjectInstructionFile(kind: kind, path: path, lastModified: lastModified)
        }
    }

    func projectConflicts(for root: ProjectSkillRoot) -> [ProjectSkillConflict] {
        projectSkills(for: root).compactMap { skill in
            guard let summary = conflictSummary(for: skill) else { return nil }
            return ProjectSkillConflict(skill: skill, summary: summary)
        }
    }

    func createCollectionFromProject(_ root: ProjectSkillRoot) -> SkillCollection {
        let skills = sortSkills(projectSkills(for: root))
        let collection = SkillCollection(
            name: uniqueCollectionName(from: root.name),
            skillPaths: skills.map(\.path),
            iconName: SkillCollectionIcon.folder.rawValue,
            accent: .blue,
            isPinned: true
        )
        collections.append(collection)
        persistCollections()
        return collection
    }

    @discardableResult
    func createProjectSkillsFolder(for root: ProjectSkillRoot) -> Bool {
        do {
            try FileManager.default.createDirectory(
                at: URL(fileURLWithPath: root.claudeSkillsPath),
                withIntermediateDirectories: true
            )
            refresh()
            startWatching()
            return true
        } catch {
            return false
        }
    }

    func projectTrustStatus(for root: ProjectSkillRoot) -> ProjectTrustStatus {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return .unavailable
        }

        guard let currentSignature = projectContentSignature(for: root) else {
            return .noTrackedFiles
        }

        guard let trustedSignature = root.trustedContentSignature else {
            return .needsReview
        }

        return currentSignature == trustedSignature ? .trusted : .needsReview
    }

    func trustCurrentProjectContent(for root: ProjectSkillRoot) {
        guard let index = projectSkillRoots.firstIndex(where: { $0.id == root.id }) else { return }
        projectSkillRoots[index].trustedContentSignature = projectContentSignature(for: projectSkillRoots[index])
        projectSkillRoots[index].updatedAt = Date()
        persistProjectSkillRoots()
    }

    func projectSkillRootStatus(for root: ProjectSkillRoot) -> ProjectSkillRootStatus {
        guard root.isEnabled else { return .disabled }

        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false

        guard fileManager.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return .missingProjectFolder
        }

        isDirectory = false
        guard fileManager.fileExists(atPath: root.claudeSkillsPath, isDirectory: &isDirectory), isDirectory.boolValue else {
            return .missingSkillsFolder
        }

        return .available
    }

    func projectSkillRoot(for section: SkillSection) -> ProjectSkillRoot? {
        section.skills.compactMap { skill -> ProjectSkillRoot? in
            guard case .claudeCode(.project(let root)) = skill.source else { return nil }
            return root
        }.first
    }

    func projectSkillRoot(for skill: Skill) -> ProjectSkillRoot? {
        guard case .claudeCode(.project(let root)) = skill.source else { return nil }
        return root
    }

    func conflictSummary(for skill: Skill) -> SkillConflictSummary? {
        guard skill.source.isProjectSkill else { return nil }

        let trigger = normalizedSearchValue(skill.triggerCommand)
        let name = normalizedSearchValue(skill.displayName)

        var triggerMatchCount = 0
        var nameMatchCount = 0
        var descriptions: [String] = []
        var conflictingPaths: [String] = []
        var seenPaths: Set<String> = []

        for candidate in lastScannedSkills where candidate.path != skill.path {
            let triggerMatches = normalizedSearchValue(candidate.triggerCommand) == trigger
            let nameMatches = normalizedSearchValue(candidate.displayName) == name
            guard triggerMatches || nameMatches else { continue }
            guard seenPaths.insert(candidate.path).inserted else { continue }

            if triggerMatches {
                triggerMatchCount += 1
            }
            if nameMatches {
                nameMatchCount += 1
            }

            let matchLabel: String
            switch (triggerMatches, nameMatches) {
            case (true, true):
                matchLabel = "same trigger and name"
            case (true, false):
                matchLabel = "same trigger"
            case (false, true):
                matchLabel = "same name"
            case (false, false):
                continue
            }

            descriptions.append("\(candidate.source.shortScopeLabel): \(candidate.displayName) (\(matchLabel))")
            conflictingPaths.append(candidate.path)
        }

        guard !descriptions.isEmpty else { return nil }

        return SkillConflictSummary(
            triggerMatchCount: triggerMatchCount,
            nameMatchCount: nameMatchCount,
            matchingSkillDescriptions: descriptions.sorted(),
            conflictingSkillPaths: conflictingPaths
        )
    }

    func firstConflictingSkill(for skill: Skill) -> Skill? {
        guard let summary = conflictSummary(for: skill) else { return nil }
        for path in summary.conflictingSkillPaths {
            if let skill = lastScannedSkills.first(where: { $0.path == path }) {
                return skill
            }
        }
        return nil
    }

    func movePinnedItem(from sourcePath: String, toIndex destinationIndex: Int) {
        guard let sourceIndex = pinnedOrder.firstIndex(of: sourcePath) else { return }
        pinnedOrder.remove(at: sourceIndex)
        let adjustedIndex = min(destinationIndex, pinnedOrder.count)
        pinnedOrder.insert(sourcePath, at: adjustedIndex)
        persistPins()
    }

    // MARK: - Collections

    func createCollection(named name: String, including skill: Skill? = nil) -> SkillCollection {
        let collection = SkillCollection(
            name: uniqueCollectionName(from: name),
            skillPaths: skill.map { [$0.path] } ?? []
        )
        collections.append(collection)
        persistCollections()
        return collection
    }

    func renameCollection(_ collection: SkillCollection, to name: String) {
        guard let index = collections.firstIndex(where: { $0.id == collection.id }) else { return }
        collections[index].name = uniqueCollectionName(from: name, excluding: collection.id)
        collections[index].updatedAt = Date()
        persistCollections()
    }

    func deleteCollection(_ collection: SkillCollection) {
        collections.removeAll { $0.id == collection.id }
        persistCollections()
    }

    func duplicateCollection(_ collection: SkillCollection) {
        let copiedCollection = SkillCollection(
            name: uniqueCollectionName(from: "\(collection.name) Copy"),
            skillPaths: collection.skillPaths,
            iconName: collection.iconName,
            accent: collection.accent
        )
        collections.append(copiedCollection)
        persistCollections()
    }

    func canMoveCollection(_ collection: SkillCollection, by offset: Int) -> Bool {
        guard let sourceIndex = collections.firstIndex(where: { $0.id == collection.id }) else { return false }
        let peerIndices = collections.indices.filter { collections[$0].isPinned == collection.isPinned }
        guard let peerPosition = peerIndices.firstIndex(of: sourceIndex) else { return false }
        return peerIndices.indices.contains(peerPosition + offset)
    }

    func moveCollection(_ collection: SkillCollection, by offset: Int) {
        guard let sourceIndex = collections.firstIndex(where: { $0.id == collection.id }) else { return }
        let peerIndices = collections.indices.filter { collections[$0].isPinned == collection.isPinned }
        guard let peerPosition = peerIndices.firstIndex(of: sourceIndex),
              peerIndices.indices.contains(peerPosition + offset) else {
            return
        }

        let destinationIndex = peerIndices[peerPosition + offset]
        collections.swapAt(sourceIndex, destinationIndex)
        collections[destinationIndex].updatedAt = Date()
        persistCollections()
    }

    func togglePinCollection(_ collection: SkillCollection) {
        guard let index = collections.firstIndex(where: { $0.id == collection.id }) else { return }
        collections[index].isPinned.toggle()
        collections[index].updatedAt = Date()
        persistCollections()
    }

    func updateCollectionAppearance(
        _ collection: SkillCollection,
        iconName: String? = nil,
        accent: SkillCollectionAccent? = nil
    ) {
        guard let index = collections.firstIndex(where: { $0.id == collection.id }) else { return }
        if let iconName {
            collections[index].iconName = iconName
        }
        if let accent {
            collections[index].accent = accent
        }
        collections[index].updatedAt = Date()
        persistCollections()
    }

    func moveSkill(_ skill: Skill, in collection: SkillCollection, before targetSkill: Skill) {
        moveSkill(skill, in: collection, relativeTo: targetSkill, shouldInsertAfterTarget: false)
    }

    func moveSkill(_ skill: Skill, in collection: SkillCollection, after targetSkill: Skill) {
        moveSkill(skill, in: collection, relativeTo: targetSkill, shouldInsertAfterTarget: true)
    }

    func removeSkill(_ skill: Skill, from collection: SkillCollection) {
        guard let collectionIndex = collections.firstIndex(where: { $0.id == collection.id }) else { return }
        collections[collectionIndex].skillPaths.removeAll { $0 == skill.path }
        collections[collectionIndex].updatedAt = Date()
        persistCollections()
    }

    @discardableResult
    func clearMissingSkills(from collection: SkillCollection) -> Int {
        guard lastRefreshDate != nil,
              let collectionIndex = collections.firstIndex(where: { $0.id == collection.id }) else {
            return 0
        }

        let availablePaths = Set(lastScannedSkills.map(\.path))
        let originalPaths = collections[collectionIndex].skillPaths
        let resolvedPaths = originalPaths.filter { availablePaths.contains($0) }
        let removedCount = originalPaths.count - resolvedPaths.count

        guard removedCount > 0 else { return 0 }

        collections[collectionIndex].skillPaths = resolvedPaths
        collections[collectionIndex].updatedAt = Date()
        persistCollections()
        return removedCount
    }

    func toggleSkill(_ skill: Skill, in collection: SkillCollection) {
        guard let index = collections.firstIndex(where: { $0.id == collection.id }) else { return }

        if let pathIndex = collections[index].skillPaths.firstIndex(of: skill.path) {
            collections[index].skillPaths.remove(at: pathIndex)
        } else {
            collections[index].skillPaths.append(skill.path)
        }

        collections[index].updatedAt = Date()
        persistCollections()
    }

    func isSkill(_ skill: Skill, in collection: SkillCollection) -> Bool {
        collection.skillPaths.contains(skill.path)
    }

    func collections(for skill: Skill) -> [SkillCollection] {
        orderedCollections.filter { $0.skillPaths.contains(skill.path) }
    }

    func skill(forPath path: String) -> Skill? {
        lastScannedSkills.first { $0.path == path }
    }

    func resolvedCollections(searchText query: String = "") -> [ResolvedSkillCollection] {
        let searchQuery = parseSkillSearchQuery(query)
        let skillLookup = Dictionary(uniqueKeysWithValues: lastScannedSkills.map { ($0.path, $0) })

        return orderedCollections.compactMap { collection in
            let resolvedSkills = collection.skillPaths.compactMap { skillLookup[$0] }
            let missingSkillPaths = collection.skillPaths.filter { skillLookup[$0] == nil }
            let missingCount = missingSkillPaths.count

            let visibleSkills: [Skill]
            if searchQuery.isEmpty {
                visibleSkills = resolvedSkills
            } else if !searchQuery.hasFilters && collection.name.lowercased().contains(searchQuery.freeText) {
                visibleSkills = resolvedSkills
            } else {
                visibleSkills = resolvedSkills.filter { skillMatchesSearch($0, query: searchQuery) }
            }

            let nameMatches = !searchQuery.hasFilters && collection.name.lowercased().contains(searchQuery.freeText)
            guard searchQuery.isEmpty || nameMatches || !visibleSkills.isEmpty else { return nil }

            return ResolvedSkillCollection(
                collection: collection,
                skills: visibleSkills,
                missingCount: missingCount,
                missingSkillPaths: missingSkillPaths
            )
        }
    }

    private func uniqueCollectionName(from proposedName: String, excluding collectionID: UUID? = nil) -> String {
        let baseName = proposedName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "New Collection"
            : proposedName.trimmingCharacters(in: .whitespacesAndNewlines)

        let existingNames = Set(
            collections
                .filter { $0.id != collectionID }
                .map { $0.name.lowercased() }
        )

        guard !existingNames.contains(baseName.lowercased()) else {
            var suffix = 2
            while existingNames.contains("\(baseName) \(suffix)".lowercased()) {
                suffix += 1
            }
            return "\(baseName) \(suffix)"
        }

        return baseName
    }

    private func removeSkillPathFromCollections(_ path: String) {
        var didChange = false

        for index in collections.indices {
            let originalCount = collections[index].skillPaths.count
            collections[index].skillPaths.removeAll { $0 == path }
            if collections[index].skillPaths.count != originalCount {
                collections[index].updatedAt = Date()
                didChange = true
            }
        }

        if didChange {
            persistCollections()
        }

        var didChangeProjectPins = false
        for key in Array(projectPinnedSkillPaths.keys) {
            let originalCount = projectPinnedSkillPaths[key]?.count ?? 0
            projectPinnedSkillPaths[key]?.removeAll { $0 == path }
            if projectPinnedSkillPaths[key]?.isEmpty == true {
                projectPinnedSkillPaths.removeValue(forKey: key)
            }
            if (projectPinnedSkillPaths[key]?.count ?? 0) != originalCount {
                didChangeProjectPins = true
            }
        }

        if didChangeProjectPins {
            persistProjectPins()
        }
    }

    private func removeSkillReferences(inside directory: String) {
        let standardizedDirectory = standardizedPath(directory)

        let removedPinnedPaths = pinnedPaths.filter { path in
            self.path(standardizedPath(path), isEqualToOrInside: standardizedDirectory)
        }

        if !removedPinnedPaths.isEmpty {
            pinnedPaths.subtract(removedPinnedPaths)
            pinnedOrder.removeAll { removedPinnedPaths.contains($0) }
            persistPins()
        }

        var didChangeCollections = false
        for index in collections.indices {
            let originalCount = collections[index].skillPaths.count
            collections[index].skillPaths.removeAll { path in
                self.path(standardizedPath(path), isEqualToOrInside: standardizedDirectory)
            }
            if collections[index].skillPaths.count != originalCount {
                collections[index].updatedAt = Date()
                didChangeCollections = true
            }
        }

        if didChangeCollections {
            persistCollections()
        }

        var didChangeProjectPins = false
        for key in Array(projectPinnedSkillPaths.keys) {
            let originalCount = projectPinnedSkillPaths[key]?.count ?? 0
            projectPinnedSkillPaths[key]?.removeAll { path in
                self.path(standardizedPath(path), isEqualToOrInside: standardizedDirectory)
            }
            if projectPinnedSkillPaths[key]?.isEmpty == true {
                projectPinnedSkillPaths.removeValue(forKey: key)
            }
            if (projectPinnedSkillPaths[key]?.count ?? 0) != originalCount {
                didChangeProjectPins = true
            }
        }

        if didChangeProjectPins {
            persistProjectPins()
        }
    }

    private func removeAgentReferences(inside directory: String) {
        let standardizedDirectory = standardizedPath(directory)

        let removedPinnedPaths = pinnedPaths.filter { path in
            self.path(standardizedPath(path), isEqualToOrInside: standardizedDirectory)
        }

        if !removedPinnedPaths.isEmpty {
            pinnedPaths.subtract(removedPinnedPaths)
            pinnedOrder.removeAll { removedPinnedPaths.contains($0) }
            persistPins()
        }
    }

    private func moveSkill(
        _ skill: Skill,
        in collection: SkillCollection,
        relativeTo targetSkill: Skill,
        shouldInsertAfterTarget: Bool
    ) {
        guard let collectionIndex = collections.firstIndex(where: { $0.id == collection.id }) else { return }
        var paths = collections[collectionIndex].skillPaths

        guard let sourceIndex = paths.firstIndex(of: skill.path),
              paths.contains(targetSkill.path),
              skill.path != targetSkill.path else {
            return
        }

        let path = paths.remove(at: sourceIndex)
        guard var targetIndex = paths.firstIndex(of: targetSkill.path) else { return }
        if shouldInsertAfterTarget {
            targetIndex += 1
        }

        paths.insert(path, at: targetIndex)
        collections[collectionIndex].skillPaths = paths
        collections[collectionIndex].updatedAt = Date()
        persistCollections()
    }

    // MARK: - Pinning (Skills)

    func isPinned(_ skill: Skill) -> Bool {
        pinnedPaths.contains(skill.path)
    }

    func togglePin(_ skill: Skill) {
        if pinnedPaths.contains(skill.path) {
            pinnedPaths.remove(skill.path)
            pinnedOrder.removeAll { $0 == skill.path }
        } else {
            pinnedPaths.insert(skill.path)
            pinnedOrder.append(skill.path)
        }
        persistPins()
    }

    // MARK: - Pinning (Agents)

    func isPinnedAgent(_ agent: Agent) -> Bool {
        pinnedPaths.contains(agent.path)
    }

    func togglePinAgent(_ agent: Agent) {
        if pinnedPaths.contains(agent.path) {
            pinnedPaths.remove(agent.path)
            pinnedOrder.removeAll { $0 == agent.path }
        } else {
            pinnedPaths.insert(agent.path)
            pinnedOrder.append(agent.path)
        }
        persistPins()
    }

    // MARK: - Filtering (Skills)

    private func parseSkillSearchQuery(_ rawValue: String) -> SkillSearchQuery {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else {
            return SkillSearchQuery(
                rawValue: "",
                freeText: "",
                terms: [],
                sourceCategories: [],
                projectTerms: []
            )
        }

        var terms: [String] = []
        var sourceCategories: Set<SkillSourceCategory> = []
        var projectTerms: [String] = []

        for token in trimmed.split(whereSeparator: \.isWhitespace).map(String.init) {
            if token.hasPrefix("source:") {
                let value = String(token.dropFirst("source:".count))
                if let category = SkillSourceCategory(rawValue: value) {
                    sourceCategories.insert(category)
                } else if value == "built-in" || value == "built_in" {
                    sourceCategories.insert(.builtin)
                }
                continue
            }

            if token.hasPrefix("project:") {
                let value = String(token.dropFirst("project:".count))
                if !value.isEmpty {
                    projectTerms.append(value)
                    sourceCategories.insert(.project)
                }
                continue
            }

            terms.append(token)
        }

        return SkillSearchQuery(
            rawValue: trimmed,
            freeText: trimmed,
            terms: terms,
            sourceCategories: sourceCategories,
            projectTerms: projectTerms
        )
    }

    private func skillMatchesSearch(_ skill: Skill, query: SkillSearchQuery) -> Bool {
        if !query.sourceCategories.isEmpty,
           !query.sourceCategories.contains(skill.source.searchCategory) {
            return false
        }

        if !query.projectTerms.isEmpty {
            guard let projectName = skill.source.projectName?.lowercased() else { return false }
            let projectPath = skill.source.projectRootPath?.lowercased() ?? ""
            guard query.projectTerms.allSatisfy({ projectName.contains($0) || projectPath.contains($0) }) else {
                return false
            }
        }

        if query.hasFilters {
            guard !query.terms.isEmpty else { return true }
            return query.terms.allSatisfy { term in
                skillSearchFields(for: skill).contains { $0.contains(term) }
            }
        }

        return skillSearchFields(for: skill).contains { $0.contains(query.freeText) }
    }

    private func skillSearchFields(for skill: Skill) -> [String] {
        [
            skill.name,
            skill.displayName,
            skill.description,
            skill.triggerCommand,
            skill.source.groupTitle,
            skill.source.sectionTitle,
            skill.source.shortScopeLabel,
            skill.source.searchCategory.rawValue,
            skill.source.projectName ?? "",
            skill.source.projectRootPath ?? "",
        ].map(normalizedSearchValue)
    }

    private func normalizedSearchValue(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    var filteredGroups: [SkillGroup] {
        let query = parseSkillSearchQuery(searchText)
        guard !query.isEmpty else { return groups }

        return groups.compactMap { group in
            let filteredSections = group.sections.compactMap { section in
                let filtered = section.skills.filter { skillMatchesSearch($0, query: query) }
                return filtered.isEmpty ? nil : SkillSection(id: section.id, title: section.title, skills: filtered)
            }
            return filteredSections.isEmpty ? nil : SkillGroup(id: group.id, title: group.title, sections: filteredSections)
        }
    }

    var totalSkillCount: Int {
        groups.reduce(0) { $0 + $1.totalCount }
    }

    var totalItemCount: Int {
        totalSkillCount + plugins.count + agentGroups.reduce(0) { $0 + $1.totalCount }
    }

    var filteredPlugins: [Plugin] {
        let query = parseSkillSearchQuery(searchText)
        guard !query.isEmpty else { return plugins }
        guard query.sourceCategories.isEmpty || query.sourceCategories.contains(.plugin) else { return [] }
        let freeText = query.hasFilters ? query.terms.joined(separator: " ") : query.freeText
        guard !freeText.isEmpty else { return plugins }

        return plugins.filter { plugin in
            plugin.displayName.lowercased().contains(freeText) ||
            plugin.name.lowercased().contains(freeText) ||
            plugin.description.lowercased().contains(freeText) ||
            plugin.shortDescription.lowercased().contains(freeText) ||
            (plugin.publisher?.lowercased().contains(freeText) ?? false) ||
            (plugin.version?.lowercased().contains(freeText) ?? false) ||
            plugin.keywords.contains(where: { $0.lowercased().contains(freeText) })
        }
    }

    func skills(for plugin: Plugin) -> [Skill] {
        let pluginPath = standardizedPath(plugin.path)
        let matchedSkills = lastScannedSkills.filter { skill in
            guard case .codexCLI(.plugin) = skill.source else { return false }
            return path(standardizedPath(skill.path), isEqualToOrInside: pluginPath)
        }
        return sortSkills(matchedSkills)
    }

    func groupsForTab(_ tab: SkillTab) -> [SkillGroup] {
        let source = filteredGroups
        var tabGroups: [SkillGroup]
        switch tab {
        case .claudeCode:
            tabGroups = source.filter { $0.id == "claude-code" }
        case .codex:
            tabGroups = source.filter { $0.id == "codex-cli" }
        case .collections:
            return []
        }

        // Build pinned section from skills in this tab, preserving custom order
        let allSkills = tabGroups.flatMap { $0.sections.flatMap { $0.skills } }
        let pinnedByPath = Dictionary(
            allSkills.filter { pinnedPaths.contains($0.path) }.map { ($0.path, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let pinned = pinnedOrder.compactMap { pinnedByPath[$0] }

        if !pinned.isEmpty {
            let pinnedPathSet = Set(pinned.map { $0.path })

            // Remove pinned skills from their original sections
            tabGroups = tabGroups.compactMap { group in
                let newSections = group.sections.compactMap { section in
                    let remaining = section.skills.filter { !pinnedPathSet.contains($0.path) }
                    return remaining.isEmpty ? nil : SkillSection(id: section.id, title: section.title, skills: remaining)
                }
                return newSections.isEmpty ? nil : SkillGroup(id: group.id, title: group.title, sections: newSections)
            }

            // Insert pinned group at top
            let pinnedSection = SkillSection(id: "pinned", title: "Pinned", skills: pinned)
            let pinnedGroup = SkillGroup(id: "pinned", title: "Pinned", sections: [pinnedSection])
            tabGroups.insert(pinnedGroup, at: 0)
        }

        return tabGroups
    }

    // MARK: - Filtering (Agents)

    var agentGroupsFiltered: [AgentGroup] {
        let query = parseSkillSearchQuery(searchText)
        guard !query.isEmpty else { return agentGroups }

        return agentGroups.compactMap { group in
            let filteredSections = group.sections.compactMap { section in
                let filtered = section.agents.filter { agentMatchesSearch($0, query: query) }
                return filtered.isEmpty ? nil : AgentSection(id: section.id, title: section.title, agents: filtered)
            }
            return filteredSections.isEmpty ? nil : AgentGroup(id: group.id, title: group.title, sections: filteredSections)
        }
    }

    private func agentMatchesSearch(_ agent: Agent, query: SkillSearchQuery) -> Bool {
        if !query.sourceCategories.isEmpty {
            let category: SkillSourceCategory
            switch agent.source {
            case .user:
                category = .user
            case .plugin:
                category = .plugin
            case .project:
                category = .project
            }

            guard query.sourceCategories.contains(category) else { return false }
        }

        if !query.projectTerms.isEmpty {
            guard let projectName = agent.source.projectName?.lowercased() else { return false }
            let projectPath = agent.source.projectRootPath?.lowercased() ?? ""
            guard query.projectTerms.allSatisfy({ projectName.contains($0) || projectPath.contains($0) }) else {
                return false
            }
        }

        if query.hasFilters {
            guard !query.terms.isEmpty else { return true }
            return query.terms.allSatisfy { term in
                agentSearchFields(for: agent).contains { $0.contains(term) }
            }
        }

        return agentSearchFields(for: agent).contains { $0.contains(query.freeText) }
    }

    private func agentSearchFields(for agent: Agent) -> [String] {
        [
            agent.name,
            agent.displayName,
            agent.description,
            agent.identifier,
            agent.source.sectionTitle,
            agent.source.projectName ?? "",
            agent.source.projectRootPath ?? "",
        ].map(normalizedSearchValue)
    }

    func agentGroupsForTab() -> [AgentGroup] {
        let source = agentGroupsFiltered
        var tabGroups = source.filter { $0.id == "agents" }

        // Build pinned section from agents, preserving custom order
        let allAgents = tabGroups.flatMap { $0.sections.flatMap { $0.agents } }
        let pinnedAgentsByPath = Dictionary(
            allAgents.filter { pinnedPaths.contains($0.path) }.map { ($0.path, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let pinned = pinnedOrder.compactMap { pinnedAgentsByPath[$0] }

        if !pinned.isEmpty {
            let pinnedPathSet = Set(pinned.map { $0.path })

            tabGroups = tabGroups.compactMap { group in
                let newSections = group.sections.compactMap { section in
                    let remaining = section.agents.filter { !pinnedPathSet.contains($0.path) }
                    return remaining.isEmpty ? nil : AgentSection(id: section.id, title: section.title, agents: remaining)
                }
                return newSections.isEmpty ? nil : AgentGroup(id: group.id, title: group.title, sections: newSections)
            }

            let pinnedSection = AgentSection(id: "pinned", title: "Pinned", agents: pinned)
            let pinnedGroup = AgentGroup(id: "pinned", title: "Pinned", sections: [pinnedSection])
            tabGroups.insert(pinnedGroup, at: 0)
        }

        return tabGroups
    }

    func countForTab(_ tab: SkillTab) -> Int {
        let allGroups = groups
        switch tab {
        case .claudeCode:
            let skillCount = allGroups.filter { $0.id == "claude-code" }.reduce(0) { $0 + $1.totalCount }
            let agentCount = agentGroups.reduce(0) { $0 + $1.totalCount }
            return skillCount + agentCount
        case .codex:
            let skillCount = allGroups.filter { $0.id == "codex-cli" }.reduce(0) { $0 + $1.totalCount }
            return skillCount + plugins.count
        case .collections:
            return collections.count
        }
    }

    // MARK: - Feature Surfaces

    var allSkills: [Skill] {
        sortSkills(lastScannedSkills)
    }

    var allAgents: [Agent] {
        lastScannedAgents.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    func skillHealthIssues(usageTracker: UsageTracker? = nil) -> [SkillHealthIssue] {
        var issues: [SkillHealthIssue] = []
        let allPaths = Set(lastScannedSkills.map(\.path) + lastScannedAgents.map(\.path))

        for skill in lastScannedSkills {
            let content = try? String(contentsOfFile: skill.path, encoding: .utf8)
            if content == nil || content.flatMap({ FrontmatterParser.parse(content: $0) }) == nil {
                issues.append(
                    SkillHealthIssue(
                        id: "invalid-frontmatter-\(skill.path)",
                        category: .invalidFrontmatter,
                        severity: .critical,
                        title: skill.displayName,
                        detail: "SKILL.md is missing valid YAML frontmatter.",
                        path: skill.path,
                        skillPath: skill.path,
                        collectionID: nil
                    )
                )
            }

            if skill.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                issues.append(
                    SkillHealthIssue(
                        id: "missing-description-\(skill.path)",
                        category: .missingDescription,
                        severity: .warning,
                        title: skill.displayName,
                        detail: "Add a description so the skill is easier to scan and validate.",
                        path: skill.path,
                        skillPath: skill.path,
                        collectionID: nil
                    )
                )
            }
        }

        for group in conflictGroups().filter({ $0.kind == .trigger }) {
            issues.append(
                SkillHealthIssue(
                    id: "duplicate-trigger-\(group.value.lowercased())",
                    category: .duplicateTrigger,
                    severity: .warning,
                    title: group.value,
                    detail: "\(group.skills.count) skills use this trigger.",
                    path: group.skills.first?.path,
                    skillPath: group.skills.first?.path,
                    collectionID: nil
                )
            )
        }

        let skillLookup = Set(lastScannedSkills.map(\.path))
        for collection in collections {
            for path in collection.skillPaths where !skillLookup.contains(path) {
                issues.append(
                    SkillHealthIssue(
                        id: "missing-collection-\(collection.id.uuidString)-\(path)",
                        category: .missingCollectionPath,
                        severity: .warning,
                        title: collection.name,
                        detail: "Saved skill path no longer resolves: \(path)",
                        path: path,
                        skillPath: nil,
                        collectionID: collection.id
                    )
                )
            }
        }

        for folder in watchedHealthFolders() {
            guard FileManager.default.fileExists(atPath: folder.path) else { continue }
            if (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) == nil {
                issues.append(
                    SkillHealthIssue(
                        id: "unreadable-folder-\(folder.path)",
                        category: .unreadableFolder,
                        severity: .critical,
                        title: folder.title,
                        detail: "SkillsBar cannot read this folder.",
                        path: folder.path,
                        skillPath: nil,
                        collectionID: nil
                    )
                )
            }
        }

        for path in pinnedPaths where !allPaths.contains(path) {
            issues.append(
                SkillHealthIssue(
                    id: "stale-pin-\(path)",
                    category: .stalePinnedItem,
                    severity: .warning,
                    title: URL(fileURLWithPath: path).lastPathComponent,
                    detail: "This pinned path is no longer in the latest scan.",
                    path: path,
                    skillPath: nil,
                    collectionID: nil
                )
            )
        }

        return issues.sorted { lhs, rhs in
            if lhs.category.title != rhs.category.title {
                return lhs.category.title < rhs.category.title
            }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }

    func clearStalePinnedItems() -> Int {
        let availablePaths = Set(lastScannedSkills.map(\.path) + lastScannedAgents.map(\.path))
        let stale = pinnedPaths.subtracting(availablePaths)
        guard !stale.isEmpty else { return 0 }
        pinnedPaths.subtract(stale)
        pinnedOrder.removeAll { stale.contains($0) }
        persistPins()
        return stale.count
    }

    @discardableResult
    func clearAllMissingCollectionPaths() -> Int {
        guard lastRefreshDate != nil else { return 0 }
        let availablePaths = Set(lastScannedSkills.map(\.path))
        var removedCount = 0

        for index in collections.indices {
            let original = collections[index].skillPaths
            let resolved = original.filter { availablePaths.contains($0) }
            removedCount += original.count - resolved.count
            if original != resolved {
                collections[index].skillPaths = resolved
                collections[index].updatedAt = Date()
            }
        }

        if removedCount > 0 {
            persistCollections()
        }

        return removedCount
    }

    func conflictGroups() -> [SkillConflictGroup] {
        let triggerGroups = Dictionary(grouping: lastScannedSkills) { skill in
            normalizedSearchValue(skill.triggerCommand)
        }
        let nameGroups = Dictionary(grouping: lastScannedSkills) { skill in
            normalizedSearchValue(skill.displayName)
        }

        let triggers = triggerGroups.compactMap { key, skills -> SkillConflictGroup? in
            guard !key.isEmpty, skills.count > 1 else { return nil }
            return SkillConflictGroup(kind: .trigger, value: skills[0].triggerCommand, skills: sortSkills(skills))
        }

        let names = nameGroups.compactMap { key, skills -> SkillConflictGroup? in
            guard !key.isEmpty, skills.count > 1 else { return nil }
            return SkillConflictGroup(kind: .name, value: skills[0].displayName, skills: sortSkills(skills))
        }

        return (triggers + names).sorted { lhs, rhs in
            if lhs.kind.title != rhs.kind.title {
                return lhs.kind.title < rhs.kind.title
            }
            return lhs.value.localizedCaseInsensitiveCompare(rhs.value) == .orderedAscending
        }
    }

    func validationSummary(for skill: Skill) -> SkillValidationSummary {
        let content = try? String(contentsOfFile: skill.path, encoding: .utf8)
        let parsed = content.flatMap { FrontmatterParser.parse(content: $0) }
        let hasFrontmatter = parsed != nil
        let hasName = !(parsed?.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        let hasDescription = !(parsed?.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        var missing: [String] = []

        if !hasName {
            missing.append("name")
        }
        if !hasDescription {
            missing.append("description")
        }

        return SkillValidationSummary(
            hasFrontmatter: hasFrontmatter,
            hasName: hasName,
            hasDescription: hasDescription,
            recommendedMissingFields: missing,
            exampleInvocation: validationExampleInvocation(for: skill),
            previewTitle: skill.displayName,
            previewDescription: skill.shortDescription.isEmpty ? "No description available." : skill.shortDescription
        )
    }

    func instructionHubItems() -> [InstructionHubItem] {
        let globalItems = GlobalInstructionsFile.allCases.map { file in
            instructionHubItem(
                displayName: file.displayName,
                sourceLabel: file == .claudeCode ? "Claude Code" : "Codex",
                scope: .global,
                projectName: nil,
                path: file.path
            )
        }

        let projectItems = orderedProjectSkillRoots.flatMap { root in
            ProjectInstructionKind.allCases.map { kind in
                instructionHubItem(
                    displayName: kind.displayName,
                    sourceLabel: kind.sourceLabel,
                    scope: .project,
                    projectName: root.name,
                    path: (root.path as NSString).appendingPathComponent(kind.relativePath)
                )
            }
        }

        return globalItems + projectItems
    }

    private func watchedHealthFolders() -> [(title: String, path: String)] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var folders = [
            ("Claude user skills", (home as NSString).appendingPathComponent(".claude/skills")),
            ("Claude plugins", (home as NSString).appendingPathComponent(".claude/plugins/cache")),
            ("Claude agents", (home as NSString).appendingPathComponent(".claude/agents")),
            ("Codex user skills", (home as NSString).appendingPathComponent(".codex/skills")),
            ("Codex plugins", (home as NSString).appendingPathComponent(".codex/plugins/cache")),
        ]

        for root in orderedProjectSkillRoots {
            folders.append(("\(root.name) project skills", root.claudeSkillsPath))
            folders.append(("\(root.name) project agents", root.claudeAgentsPath))
        }

        return folders
    }

    private func validationExampleInvocation(for skill: Skill) -> String {
        switch skill.source {
        case .claudeCode:
            return "Claude Code: \(skill.triggerCommand)"
        case .codexCLI:
            return "Codex: \(skill.triggerCommand)"
        }
    }

    private func instructionHubItem(
        displayName: String,
        sourceLabel: String,
        scope: InstructionHubScope,
        projectName: String?,
        path: String
    ) -> InstructionHubItem {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && !isDirectory.boolValue
        let isReadable = exists && FileManager.default.isReadableFile(atPath: path)
        let attributes = try? FileManager.default.attributesOfItem(atPath: path)
        let size = attributes?[.size] as? UInt64 ?? 0
        return InstructionHubItem(
            id: path,
            displayName: displayName,
            sourceLabel: sourceLabel,
            scope: scope,
            projectName: projectName,
            path: path,
            exists: exists,
            lastModified: attributes?[.modificationDate] as? Date,
            isReadable: isReadable,
            isEmpty: exists && size == 0
        )
    }

    enum SkillTab: String, CaseIterable, Identifiable {
        case claudeCode = "Claude Code"
        case codex = "Codex"
        case collections = "Collections"

        var id: String { rawValue }
    }

    // MARK: - Lifecycle

    func start() {
        refresh()
        startWatching()
    }

    func refresh() {
        guard refreshTask == nil else {
            pendingRefresh = true
            isRefreshing = true
            return
        }

        isRefreshing = true
        let projectSkillRoots = self.projectSkillRoots

        refreshTask = Task(priority: .userInitiated) { [weak self] in
            let scanned = await Task.detached(priority: .userInitiated) {
                Self.scanContent(projectSkillRoots: projectSkillRoots)
            }.value

            guard let self else { return }

            self.lastScannedSkills = scanned.skills
            self.lastScannedAgents = scanned.agents
            self.groups = self.buildGroups(from: scanned.skills)
            self.agentGroups = self.buildAgentGroups(from: scanned.agents)
            self.plugins = scanned.plugins
            self.lastRefreshDate = Date()
            self.refreshTask = nil

            if self.pendingRefresh {
                self.pendingRefresh = false
                self.refresh()
            } else {
                self.isRefreshing = false
            }
        }
    }

    private func refreshGroups() {
        guard !lastScannedSkills.isEmpty else { return }
        groups = buildGroups(from: lastScannedSkills)
    }

    @discardableResult
    func deleteSkill(_ skill: Skill) -> Bool {
        guard !skill.source.isProjectSkill else { return false }

        let fileManager = FileManager.default
        let skillDir = (skill.path as NSString).deletingLastPathComponent

        do {
            try fileManager.trashItem(at: URL(fileURLWithPath: skillDir), resultingItemURL: nil)
        } catch {
            return false
        }

        pinnedPaths.remove(skill.path)
        pinnedOrder.removeAll { $0 == skill.path }
        persistPins()
        removeSkillPathFromCollections(skill.path)
        refresh()
        return true
    }

    @discardableResult
    func deleteAgent(_ agent: Agent) -> Bool {
        let fileManager = FileManager.default

        do {
            try fileManager.trashItem(at: URL(fileURLWithPath: agent.path), resultingItemURL: nil)
        } catch {
            return false
        }

        pinnedPaths.remove(agent.path)
        pinnedOrder.removeAll { $0 == agent.path }
        persistPins()
        refresh()
        return true
    }

    @discardableResult
    static func open(_ url: URL, in editor: ExternalEditor) -> Bool {
        if let applicationURL = editor.applicationURL {
            NSWorkspace.shared.open(
                [url],
                withApplicationAt: applicationURL,
                configuration: NSWorkspace.OpenConfiguration()
            )
            return true
        }

        return NSWorkspace.shared.open(url)
    }

    static func openSkill(_ skill: Skill, in editor: ExternalEditor) {
        open(URL(fileURLWithPath: skill.path), in: editor)
    }

    static func revealInFinder(_ skill: Skill) {
        NSWorkspace.shared.selectFile(skill.path, inFileViewerRootedAtPath: "")
    }

    static func openAgent(_ agent: Agent, in editor: ExternalEditor) {
        open(URL(fileURLWithPath: agent.path), in: editor)
    }

    static func revealAgentInFinder(_ agent: Agent) {
        NSWorkspace.shared.selectFile(agent.path, inFileViewerRootedAtPath: "")
    }

    static func openPlugin(_ plugin: Plugin, in editor: ExternalEditor) {
        open(URL(fileURLWithPath: plugin.path), in: editor)
    }

    static func revealPluginInFinder(_ plugin: Plugin) {
        NSWorkspace.shared.selectFile(plugin.path, inFileViewerRootedAtPath: "")
    }

    static func openProject(_ root: ProjectSkillRoot, in editor: ExternalEditor) {
        open(URL(fileURLWithPath: root.path), in: editor)
    }

    static func openProjectInClaudeCode(_ root: ProjectSkillRoot) {
        runTerminalCommand("claude .", in: root.path)
    }

    static func openProjectInCodex(_ root: ProjectSkillRoot) {
        runTerminalCommand("codex .", in: root.path)
    }

    static func openProjectSkillsFolder(_ root: ProjectSkillRoot, in editor: ExternalEditor) {
        open(URL(fileURLWithPath: root.claudeSkillsPath), in: editor)
    }

    static func openProjectAgentsFolder(_ root: ProjectSkillRoot, in editor: ExternalEditor) {
        open(URL(fileURLWithPath: root.claudeAgentsPath), in: editor)
    }

    static func revealProjectInFinder(_ root: ProjectSkillRoot) {
        NSWorkspace.shared.selectFile(root.path, inFileViewerRootedAtPath: "")
    }

    static func revealProjectSkillsFolderInFinder(_ root: ProjectSkillRoot) {
        NSWorkspace.shared.selectFile(root.claudeSkillsPath, inFileViewerRootedAtPath: "")
    }

    static func revealProjectAgentsFolderInFinder(_ root: ProjectSkillRoot) {
        NSWorkspace.shared.selectFile(root.claudeAgentsPath, inFileViewerRootedAtPath: "")
    }

    private static func runTerminalCommand(_ command: String, in directory: String) {
        let fullCommand = "cd \(shellQuoted(directory)) && \(command)"
        let escapedCommand = fullCommand
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = [
            "-e",
            "tell application \"Terminal\" to do script \"\(escapedCommand)\"",
            "-e",
            "tell application \"Terminal\" to activate",
        ]
        try? process.run()
    }

    private static func shellQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    // MARK: - Global Instructions Files

    enum GlobalInstructionsFile: String, CaseIterable, Identifiable {
        case claudeCode
        case codex

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .claudeCode: return "Global CLAUDE.md"
            case .codex:      return "Global AGENTS.md"
            }
        }

        var path: String {
            switch self {
            case .claudeCode: return ("~/.claude/CLAUDE.md" as NSString).expandingTildeInPath
            case .codex:      return ("~/.codex/AGENTS.md"  as NSString).expandingTildeInPath
            }
        }
    }

    static func openInstructionsFile(_ file: GlobalInstructionsFile, in editor: ExternalEditor) {
        open(URL(fileURLWithPath: file.path), in: editor)
    }

    // MARK: - Watching

    private func startWatching() {
        watchedRefreshTask?.cancel()
        watchedRefreshTask = nil
        watcher?.stop()

        let fileManager = FileManager.default
        let home = fileManager.homeDirectoryForCurrentUser.path
        let claudeRoot = (home as NSString).appendingPathComponent(".claude")
        let codexRoot = (home as NSString).appendingPathComponent(".codex")

        var targetPaths = [
            (home as NSString).appendingPathComponent(".claude/skills"),
            (home as NSString).appendingPathComponent(".claude/plugins/cache"),
            (home as NSString).appendingPathComponent(".claude/agents"),
            (home as NSString).appendingPathComponent(".codex/skills"),
            (home as NSString).appendingPathComponent(".codex/plugins/cache"),
        ].map { standardizedPath($0) }

        for root in enabledProjectSkillRoots {
            targetPaths.append(standardizedPath(root.claudeSkillsPath))
            targetPaths.append(standardizedPath(root.claudeAgentsPath))
            targetPaths.append(contentsOf: root.instructionCandidatePaths.map(standardizedPath))
        }

        watchedRefreshPrefixes = targetPaths
        watchedCreationMarkers = []

        var watchPaths = targetPaths

        let claudeTargets = targetPaths.filter { path($0, isEqualToOrInside: standardizedPath(claudeRoot)) }
        if claudeTargets.contains(where: { !fileManager.fileExists(atPath: $0) }) {
            if fileManager.fileExists(atPath: claudeRoot) {
                watchPaths.append(standardizedPath(claudeRoot))
            } else {
                watchPaths.append(standardizedPath(home))
                watchedCreationMarkers.insert(standardizedPath(claudeRoot))
            }
        }

        let codexTargets = targetPaths.filter { path($0, isEqualToOrInside: standardizedPath(codexRoot)) }
        if codexTargets.contains(where: { !fileManager.fileExists(atPath: $0) }) {
            if fileManager.fileExists(atPath: codexRoot) {
                watchPaths.append(standardizedPath(codexRoot))
            } else {
                watchPaths.append(standardizedPath(home))
                watchedCreationMarkers.insert(standardizedPath(codexRoot))
            }
        }

        for root in enabledProjectSkillRoots {
            let projectPath = standardizedPath(root.path)
            let projectClaudeRoot = standardizedPath((projectPath as NSString).appendingPathComponent(".claude"))
            let projectSkillsPath = standardizedPath(root.claudeSkillsPath)
            let projectAgentsPath = standardizedPath(root.claudeAgentsPath)

            if fileManager.fileExists(atPath: projectPath) {
                watchPaths.append(projectPath)
            }

            if fileManager.fileExists(atPath: projectSkillsPath) {
                watchPaths.append(projectSkillsPath)
            } else if fileManager.fileExists(atPath: projectClaudeRoot) {
                watchPaths.append(projectClaudeRoot)
                watchedCreationMarkers.insert(projectSkillsPath)
            } else if fileManager.fileExists(atPath: projectPath) {
                watchPaths.append(projectPath)
                watchedCreationMarkers.insert(projectClaudeRoot)
                watchedCreationMarkers.insert(projectSkillsPath)
            }

            if fileManager.fileExists(atPath: projectAgentsPath) {
                watchPaths.append(projectAgentsPath)
            } else if fileManager.fileExists(atPath: projectClaudeRoot) {
                watchPaths.append(projectClaudeRoot)
                watchedCreationMarkers.insert(projectAgentsPath)
            }
        }

        watchPaths = dedupePaths(watchPaths)

        watcher = FSEventsWatcher(paths: watchPaths) { [weak self] changedPaths in
            guard let self else { return }
            guard self.shouldRefresh(for: changedPaths) else { return }
            self.scheduleWatchedRefresh()
        }
        watcher?.start()
    }

    private func scheduleWatchedRefresh() {
        watchedRefreshTask?.cancel()
        watchedRefreshTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.watchedRefreshDelay)
            guard !Task.isCancelled else { return }

            await MainActor.run {
                self?.watchedRefreshTask = nil
                self?.refresh()
            }
        }
    }

    private func shouldRefresh(for changedPaths: [String]) -> Bool {
        // Fall back to refreshing if event paths are unavailable.
        guard !changedPaths.isEmpty else { return true }

        for changedPath in changedPaths.map(standardizedPath) {
            if watchedCreationMarkers.contains(changedPath) {
                return true
            }

            if watchedRefreshPrefixes.contains(where: { path(changedPath, isEqualToOrInside: $0) }) {
                return true
            }
        }

        return false
    }

    private func standardizedPath(_ path: String) -> String {
        (path as NSString).standardizingPath
    }

    private func path(_ path: String, isEqualToOrInside base: String) -> Bool {
        path == base || path.hasPrefix(base + "/")
    }

    private func dedupePaths(_ paths: [String]) -> [String] {
        var seen: Set<String> = []
        var deduped: [String] = []

        for path in paths.map(standardizedPath) where seen.insert(path).inserted {
            deduped.append(path)
        }

        return deduped
    }

    private func projectContentSignature(for root: ProjectSkillRoot) -> String? {
        let components = projectTrustFingerprintComponents(for: root)
        guard !components.isEmpty else { return nil }
        let data = components.joined(separator: "\n").data(using: .utf8) ?? Data()
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func projectTrustFingerprintComponents(for root: ProjectSkillRoot) -> [String] {
        let fileManager = FileManager.default
        let rootPath = standardizedPath(root.path)
        var components: [String] = []

        func appendFile(_ path: String) {
            let standardized = standardizedPath(path)
            guard let attributes = try? fileManager.attributesOfItem(atPath: standardized),
                  let fileType = attributes[.type] as? FileAttributeType,
                  fileType == .typeRegular else {
                return
            }

            let size = attributes[.size] as? UInt64 ?? 0
            let modified = (attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
            let relativePath: String
            if standardized.hasPrefix(rootPath + "/") {
                relativePath = String(standardized.dropFirst(rootPath.count + 1))
            } else {
                relativePath = standardized
            }
            components.append("\(relativePath)|\(size)|\(modified)")
        }

        for path in root.instructionCandidatePaths {
            appendFile(path)
        }

        func appendRecursiveFiles(in directory: String, includeSkillFiles: Bool) {
            guard fileManager.fileExists(atPath: directory),
                  let enumerator = fileManager.enumerator(atPath: directory) else {
                return
            }

            while let relativePath = enumerator.nextObject() as? String {
                let filename = (relativePath as NSString).lastPathComponent
                guard !filename.hasPrefix(".") else { continue }
                if !includeSkillFiles && filename == "SKILL.md" {
                    continue
                }
                appendFile((directory as NSString).appendingPathComponent(relativePath))
            }
        }

        appendRecursiveFiles(in: root.claudeSkillsPath, includeSkillFiles: false)
        appendRecursiveFiles(in: root.claudeAgentsPath, includeSkillFiles: true)

        return components.sorted()
    }

    nonisolated private static func scanContent(projectSkillRoots: [ProjectSkillRoot]) -> (skills: [Skill], agents: [Agent], plugins: [Plugin]) {
        let skills = SkillScanner().scanAll(projectSkillRoots: projectSkillRoots)
        let agents = AgentScanner().scanAll(projectSkillRoots: projectSkillRoots)
        let plugins = PluginScanner().scanInstalledPlugins()
        return (skills, agents, plugins)
    }

    // MARK: - Grouping (Skills)

    private func sortSkills(_ skills: [Skill]) -> [Skill] {
        switch sortOption {
        case .nameAsc:
            return skills.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .recentlyModified:
            return skills.sorted { a, b in
                switch (a.lastModified, b.lastModified) {
                case let (aDate?, bDate?):
                    return aDate > bDate
                case (_?, nil):
                    return true
                case (nil, _?):
                    return false
                case (nil, nil):
                    return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
                }
            }
        case .mostUsed:
            return skills.sorted { a, b in
                let aCount = usageTracker?.stat(for: a)?.totalCount ?? 0
                let bCount = usageTracker?.stat(for: b)?.totalCount ?? 0
                if aCount != bCount { return aCount > bCount }
                return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            }
        }
    }

    private func buildGroups(from skills: [Skill]) -> [SkillGroup] {
        var claudeUserSkills: [Skill] = []
        var claudePluginSkills: [Skill] = []
        var claudeProjectSkillsByRoot: [ProjectSkillRoot: [Skill]] = [:]
        var codexBuiltinSkills: [Skill] = []
        var codexPluginSkills: [Skill] = []
        var codexUserSkills: [Skill] = []

        for skill in skills {
            switch skill.source {
            case .claudeCode(.user): claudeUserSkills.append(skill)
            case .claudeCode(.plugin): claudePluginSkills.append(skill)
            case .claudeCode(.project(let root)): claudeProjectSkillsByRoot[root, default: []].append(skill)
            case .codexCLI(.builtin): codexBuiltinSkills.append(skill)
            case .codexCLI(.plugin): codexPluginSkills.append(skill)
            case .codexCLI(.user): codexUserSkills.append(skill)
            }
        }

        var groups: [SkillGroup] = []

        var claudeSections = [
            claudeUserSkills.isEmpty ? nil : SkillSection(id: "claude-user", title: "User Skills", skills: sortSkills(claudeUserSkills)),
        ].compactMap { $0 }

        let projectSections = orderedProjectSkillRoots.compactMap { root -> SkillSection? in
            guard let skills = claudeProjectSkillsByRoot[root], !skills.isEmpty else { return nil }
            return
                SkillSection(
                    id: "claude-project-\(root.id.uuidString)",
                    title: "\(root.name) Project Skills",
                    skills: sortSkills(skills)
                )
        }

        claudeSections.append(contentsOf: projectSections)

        if !claudePluginSkills.isEmpty {
            claudeSections.append(SkillSection(id: "claude-plugin", title: "Plugin Skills", skills: sortSkills(claudePluginSkills)))
        }

        if !claudeSections.isEmpty {
            groups.append(SkillGroup(id: "claude-code", title: "Claude Code", sections: claudeSections))
        }

        let codexSections = [
            codexUserSkills.isEmpty ? nil : SkillSection(id: "codex-user", title: "User Skills", skills: sortSkills(codexUserSkills)),
            codexPluginSkills.isEmpty ? nil : SkillSection(id: "codex-plugin", title: "Plugin Skills", skills: sortSkills(codexPluginSkills)),
            codexBuiltinSkills.isEmpty ? nil : SkillSection(id: "codex-builtin", title: "Built-in Skills", skills: sortSkills(codexBuiltinSkills)),
        ].compactMap { $0 }

        if !codexSections.isEmpty {
            groups.append(SkillGroup(id: "codex-cli", title: "Codex", sections: codexSections))
        }

        return groups
    }

    // MARK: - Grouping (Agents)

    private func buildAgentGroups(from agents: [Agent]) -> [AgentGroup] {
        var userAgents: [Agent] = []
        var pluginAgents: [Agent] = []
        var projectAgentsByRoot: [ProjectSkillRoot: [Agent]] = [:]

        for agent in agents {
            switch agent.source {
            case .user: userAgents.append(agent)
            case .plugin: pluginAgents.append(agent)
            case .project(let root): projectAgentsByRoot[root, default: []].append(agent)
            }
        }

        var sections = [
            userAgents.isEmpty ? nil : AgentSection(id: "agent-user", title: "User Agents", agents: userAgents.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }),
        ].compactMap { $0 }

        let projectSections = orderedProjectSkillRoots.compactMap { root -> AgentSection? in
            guard let agents = projectAgentsByRoot[root], !agents.isEmpty else { return nil }
            return AgentSection(
                id: "agent-project-\(root.id.uuidString)",
                title: "\(root.name) Project Agents",
                agents: agents.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            )
        }

        sections.append(contentsOf: projectSections)

        if !pluginAgents.isEmpty {
            sections.append(AgentSection(
                id: "agent-plugin",
                title: "Plugin Agents",
                agents: pluginAgents.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            ))
        }

        if sections.isEmpty { return [] }
        return [AgentGroup(id: "agents", title: "Agents", sections: sections)]
    }
}
