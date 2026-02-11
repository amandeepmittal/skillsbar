import Foundation
import SwiftUI

enum AgentModel: String, Hashable {
    case sonnet
    case opus
    case inherit

    var displayName: String {
        switch self {
        case .sonnet: return "Sonnet"
        case .opus: return "Opus"
        case .inherit: return "Inherit"
        }
    }
}

enum AgentColor: String, Hashable {
    case cyan
    case green
    case magenta
    case pink
    case red
    case yellow

    var swiftUIColor: Color {
        switch self {
        case .cyan: return .cyan
        case .green: return .green
        case .magenta: return Color(red: 0.8, green: 0.2, blue: 0.6)
        case .pink: return .pink
        case .red: return .red
        case .yellow: return .yellow
        }
    }
}

struct Agent: Identifiable, Hashable {
    let id: String
    let name: String
    let description: String
    let source: AgentSource
    let path: String
    var model: AgentModel?
    var color: AgentColor?
    var tools: [String] = []
    var body: String = ""
    var lastModified: Date?

    init(name: String, description: String, source: AgentSource, path: String, model: AgentModel? = nil, color: AgentColor? = nil, tools: [String] = [], body: String = "", lastModified: Date? = nil) {
        self.id = path
        self.name = name
        self.description = description
        self.source = source
        self.path = path
        self.model = model
        self.color = color
        self.tools = tools
        self.body = body
        self.lastModified = lastModified
    }

    var displayName: String {
        name.isEmpty ? identifier : name
    }

    var identifier: String {
        let filename = URL(fileURLWithPath: path).lastPathComponent
        if filename.hasSuffix(".md") {
            return String(filename.dropLast(3))
        }
        return filename
    }

    var shortDescription: String {
        let firstLine = description.components(separatedBy: .newlines).first ?? description
        if firstLine.count > 120 {
            return String(firstLine.prefix(117)) + "..."
        }
        return firstLine
    }

    var isNew: Bool {
        guard let date = lastModified else { return false }
        return Date().timeIntervalSince(date) < 86400
    }

    var formattedLastModified: String? {
        guard let date = lastModified else { return nil }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
