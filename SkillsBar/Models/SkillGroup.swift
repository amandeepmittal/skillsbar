import Foundation

struct SkillGroup: Identifiable {
    let id: String
    let title: String
    let sections: [SkillSection]

    var totalCount: Int {
        sections.reduce(0) { $0 + $1.skills.count }
    }
}

struct SkillSection: Identifiable {
    let id: String
    let title: String
    let skills: [Skill]
}
