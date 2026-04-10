import Foundation

struct SkillCollection: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var skillPaths: [String]
    let createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        skillPaths: [String] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.skillPaths = skillPaths
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

struct ResolvedSkillCollection: Identifiable {
    let collection: SkillCollection
    let skills: [Skill]
    let missingCount: Int

    var id: UUID { collection.id }
}
