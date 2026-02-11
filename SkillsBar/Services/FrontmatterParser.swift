import Foundation

struct FrontmatterParser {
    struct Result {
        var name: String = ""
        var description: String = ""
        var version: String?
        var body: String = ""
    }

    struct AgentResult {
        var name: String = ""
        var description: String = ""
        var model: AgentModel?
        var color: AgentColor?
        var tools: [String] = []
        var body: String = ""
    }

    /// Parses YAML frontmatter from a SKILL.md file.
    /// Expects `---` delimiters with key: value lines between them.
    static func parse(content: String) -> Result? {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("---") else { return nil }

        let lines = trimmed.components(separatedBy: .newlines)
        guard lines.count >= 3 else { return nil }

        var result = Result()
        var foundEnd = false
        var endIndex = 0

        for (index, line) in lines.dropFirst().enumerated() {
            let stripped = line.trimmingCharacters(in: .whitespaces)

            if stripped == "---" {
                foundEnd = true
                endIndex = index + 2 // +1 for dropFirst, +1 for next line
                break
            }

            guard let colonIndex = stripped.firstIndex(of: ":") else { continue }
            let key = stripped[stripped.startIndex..<colonIndex]
                .trimmingCharacters(in: .whitespaces)
                .lowercased()
            let value = stripped[stripped.index(after: colonIndex)...]
                .trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))

            switch key {
            case "name":
                result.name = value
            case "description":
                result.description = value
            case "version":
                result.version = value
            default:
                break
            }
        }

        guard foundEnd else { return nil }

        // Capture body after frontmatter
        if endIndex < lines.count {
            result.body = lines[endIndex...].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return result
    }

    /// Parses YAML frontmatter from an agent markdown file.
    /// Agent frontmatter may include: name, description, model, color, tools.
    /// Supports multiline description with `|` or `>` block scalars.
    static func parseAgent(content: String) -> AgentResult? {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("---") else { return nil }

        let lines = trimmed.components(separatedBy: .newlines)
        guard lines.count >= 3 else { return nil }

        var result = AgentResult()
        var foundEnd = false
        var endIndex = 0
        var collectingMultilineDesc = false
        var multilineDescLines: [String] = []

        for (index, line) in lines.dropFirst().enumerated() {
            let stripped = line.trimmingCharacters(in: .whitespaces)

            if stripped == "---" {
                if collectingMultilineDesc {
                    result.description = multilineDescLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                    collectingMultilineDesc = false
                }
                foundEnd = true
                endIndex = index + 2
                break
            }

            // If we're collecting multiline description lines
            if collectingMultilineDesc {
                // Indented lines continue the block
                if line.hasPrefix("  ") || line.hasPrefix("\t") {
                    multilineDescLines.append(line.trimmingCharacters(in: .whitespaces))
                } else {
                    // Non-indented line ends the block
                    result.description = multilineDescLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                    collectingMultilineDesc = false
                    // Fall through to parse this line as a new key
                }
            }

            if !collectingMultilineDesc {
                guard let colonIndex = stripped.firstIndex(of: ":") else { continue }
                let key = stripped[stripped.startIndex..<colonIndex]
                    .trimmingCharacters(in: .whitespaces)
                    .lowercased()
                let value = stripped[stripped.index(after: colonIndex)...]
                    .trimmingCharacters(in: .whitespaces)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))

                switch key {
                case "name":
                    result.name = value
                case "description":
                    if value == "|" || value == ">" {
                        collectingMultilineDesc = true
                        multilineDescLines = []
                    } else {
                        result.description = value
                    }
                case "model":
                    result.model = AgentModel(rawValue: value.lowercased())
                case "color":
                    result.color = AgentColor(rawValue: value.lowercased())
                case "tools":
                    result.tools = parseToolsList(value)
                default:
                    break
                }
            }
        }

        guard foundEnd else { return nil }

        if endIndex < lines.count {
            result.body = lines[endIndex...].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return result
    }

    private static func parseToolsList(_ value: String) -> [String] {
        let trimmed = value.trimmingCharacters(in: .whitespaces)

        // Handle JSON array format: ["Glob", "Grep", "Read"]
        if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
            let inner = String(trimmed.dropFirst().dropLast())
            return inner.components(separatedBy: ",")
                .map { $0.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\"'")) }
                .filter { !$0.isEmpty }
        }

        // Handle comma-separated format: Glob, Grep, Read
        if trimmed.contains(",") {
            return trimmed.components(separatedBy: ",")
                .map { $0.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\"'")) }
                .filter { !$0.isEmpty }
        }

        // Single tool or empty
        if trimmed.isEmpty { return [] }
        return [trimmed]
    }

    /// Parses Codex `agents/openai.yaml` for display_name and short_description.
    static func parseOpenAIAgent(content: String) -> (displayName: String?, shortDescription: String?) {
        var displayName: String?
        var shortDescription: String?

        for line in content.components(separatedBy: .newlines) {
            let stripped = line.trimmingCharacters(in: .whitespaces)
            if stripped.hasPrefix("display_name:") {
                displayName = String(stripped.dropFirst("display_name:".count))
                    .trimmingCharacters(in: .whitespaces)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            } else if stripped.hasPrefix("short_description:") {
                shortDescription = String(stripped.dropFirst("short_description:".count))
                    .trimmingCharacters(in: .whitespaces)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            }
        }

        return (displayName, shortDescription)
    }
}
