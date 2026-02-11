import Foundation

struct AgentScanner {
    private let fileManager = FileManager.default
    private let home = FileManager.default.homeDirectoryForCurrentUser.path

    func scanAll() -> [Agent] {
        var agents: [Agent] = []
        agents.append(contentsOf: scanUserAgents())
        agents.append(contentsOf: scanPluginAgents())
        return agents
    }

    /// Scans ~/.claude/agents/*.md for user-created agents
    func scanUserAgents() -> [Agent] {
        let dir = (home as NSString).appendingPathComponent(".claude/agents")
        guard fileManager.fileExists(atPath: dir) else { return [] }
        guard let children = try? fileManager.contentsOfDirectory(atPath: dir) else { return [] }

        var agents: [Agent] = []
        for child in children where child.hasSuffix(".md") && !child.hasPrefix(".") {
            let fullPath = (dir as NSString).appendingPathComponent(child)
            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: fullPath, isDirectory: &isDir), !isDir.boolValue else { continue }
            if let agent = parseAgentMD(at: fullPath, source: .user) {
                agents.append(agent)
            }
        }
        return agents
    }

    /// Recursively scans ~/.claude/plugins/cache/ for files matching */agents/*.md
    func scanPluginAgents() -> [Agent] {
        let dir = (home as NSString).appendingPathComponent(".claude/plugins/cache")
        guard fileManager.fileExists(atPath: dir) else { return [] }
        guard let enumerator = fileManager.enumerator(atPath: dir) else { return [] }

        var agents: [Agent] = []
        while let relativePath = enumerator.nextObject() as? String {
            let filename = (relativePath as NSString).lastPathComponent
            guard filename.hasSuffix(".md") && !filename.hasPrefix(".") else { continue }

            // Check that this file is inside an "agents" directory
            let parentDir = (relativePath as NSString).deletingLastPathComponent
            guard (parentDir as NSString).lastPathComponent == "agents" else { continue }

            let fullPath = (dir as NSString).appendingPathComponent(relativePath)
            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: fullPath, isDirectory: &isDir), !isDir.boolValue else { continue }

            if let agent = parseAgentMD(at: fullPath, source: .plugin) {
                agents.append(agent)
            }
        }
        return agents
    }

    // MARK: - Helpers

    private func parseAgentMD(at path: String, source: AgentSource) -> Agent? {
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        guard let parsed = FrontmatterParser.parseAgent(content: content) else {
            // If no valid frontmatter, still create an agent with filename
            let filename = URL(fileURLWithPath: path).lastPathComponent
            let name = filename.hasSuffix(".md") ? String(filename.dropLast(3)) : filename
            return Agent(name: name, description: "", source: source, path: path)
        }

        var name = parsed.name
        if name.isEmpty {
            let filename = URL(fileURLWithPath: path).lastPathComponent
            name = filename.hasSuffix(".md") ? String(filename.dropLast(3)) : filename
        }

        let lastModified = (try? fileManager.attributesOfItem(atPath: path))?[.modificationDate] as? Date

        return Agent(
            name: name,
            description: parsed.description,
            source: source,
            path: path,
            model: parsed.model,
            color: parsed.color,
            tools: parsed.tools,
            body: parsed.body,
            lastModified: lastModified
        )
    }
}
