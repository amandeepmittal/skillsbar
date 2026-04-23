import Foundation
import SwiftUI

enum SkillCollectionAccent: String, CaseIterable, Codable, Identifiable, Hashable {
    case blue
    case purple
    case teal
    case green
    case orange
    case pink
    case gray

    var id: String { rawValue }

    var title: String {
        switch self {
        case .blue: return "Blue"
        case .purple: return "Purple"
        case .teal: return "Teal"
        case .green: return "Green"
        case .orange: return "Orange"
        case .pink: return "Pink"
        case .gray: return "Gray"
        }
    }

    var swiftUIColor: Color {
        switch self {
        case .blue: return .blue
        case .purple: return .purple
        case .teal: return .teal
        case .green: return .green
        case .orange: return .orange
        case .pink: return .pink
        case .gray: return .gray
        }
    }
}

enum SkillCollectionIcon: String, CaseIterable, Identifiable, Hashable {
    case stack = "square.stack.3d.up"
    case folder = "folder"
    case bookmark = "bookmark"
    case document = "doc.text"
    case terminal = "terminal"
    case tools = "hammer"
    case package = "shippingbox"
    case sparkles = "sparkles"
    case magic = "wand.and.stars"
    case settings = "gearshape"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .stack: return "Stack"
        case .folder: return "Folder"
        case .bookmark: return "Bookmark"
        case .document: return "Document"
        case .terminal: return "Terminal"
        case .tools: return "Tools"
        case .package: return "Package"
        case .sparkles: return "Sparkles"
        case .magic: return "Magic"
        case .settings: return "Settings"
        }
    }
}

struct SkillCollection: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var skillPaths: [String]
    var iconName: String
    var accent: SkillCollectionAccent
    var isPinned: Bool
    let createdAt: Date
    var updatedAt: Date

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case skillPaths
        case iconName
        case accent
        case isPinned
        case createdAt
        case updatedAt
    }

    init(
        id: UUID = UUID(),
        name: String,
        skillPaths: [String] = [],
        iconName: String = SkillCollectionIcon.stack.rawValue,
        accent: SkillCollectionAccent = .blue,
        isPinned: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.skillPaths = skillPaths
        self.iconName = iconName
        self.accent = accent
        self.isPinned = isPinned
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decode(String.self, forKey: .name)
        skillPaths = try container.decodeIfPresent([String].self, forKey: .skillPaths) ?? []
        iconName = try container.decodeIfPresent(String.self, forKey: .iconName) ?? SkillCollectionIcon.stack.rawValue
        accent = try container.decodeIfPresent(SkillCollectionAccent.self, forKey: .accent) ?? .blue
        isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
    }
}

struct ResolvedSkillCollection: Identifiable {
    let collection: SkillCollection
    let skills: [Skill]
    let missingCount: Int
    let missingSkillPaths: [String]

    var id: UUID { collection.id }
}
