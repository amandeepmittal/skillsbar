import Foundation

struct AgentGroup: Identifiable {
    let id: String
    let title: String
    let sections: [AgentSection]

    var totalCount: Int {
        sections.reduce(0) { $0 + $1.agents.count }
    }
}

struct AgentSection: Identifiable {
    let id: String
    let title: String
    let agents: [Agent]
}
