import Foundation

struct SkillScanner {
    private let fileManager = FileManager.default
    private let home = FileManager.default.homeDirectoryForCurrentUser.path

    func scanAll() -> [Skill] {
        var skills: [Skill] = []
        skills.append(contentsOf: scanClaudeCodeUserSkills())
        skills.append(contentsOf: scanClaudeCodePluginSkills())
        skills.append(contentsOf: scanCodexBuiltInSkills())
        skills.append(contentsOf: scanCodexUserSkills())
        return skills
    }

    // MARK: - Claude Code

    /// Scans ~/.claude/skills/ for direct child folders containing SKILL.md
    func scanClaudeCodeUserSkills() -> [Skill] {
        let dir = (home as NSString).appendingPathComponent(".claude/skills")
        return scanDirectChildren(dir: dir, source: .claudeCode(.user))
    }

    /// Recursively scans ~/.claude/plugins/cache/ for any SKILL.md files
    func scanClaudeCodePluginSkills() -> [Skill] {
        let dir = (home as NSString).appendingPathComponent(".claude/plugins/cache")
        guard fileManager.fileExists(atPath: dir) else { return [] }

        var skills: [Skill] = []
        guard let enumerator = fileManager.enumerator(atPath: dir) else { return [] }

        while let relativePath = enumerator.nextObject() as? String {
            guard (relativePath as NSString).lastPathComponent == "SKILL.md" else { continue }
            let fullPath = (dir as NSString).appendingPathComponent(relativePath)
            if let skill = parseSkillMD(at: fullPath, source: .claudeCode(.plugin)) {
                skills.append(skill)
            }
        }

        return skills
    }

    // MARK: - Codex CLI

    /// Scans ~/.codex/skills/.system/ for built-in skills
    func scanCodexBuiltInSkills() -> [Skill] {
        let dir = (home as NSString).appendingPathComponent(".codex/skills/.system")
        return scanDirectChildren(dir: dir, source: .codexCLI(.builtin), checkAgentYaml: true)
    }

    /// Scans ~/.codex/skills/ for user-installed skills (excluding .system)
    func scanCodexUserSkills() -> [Skill] {
        let dir = (home as NSString).appendingPathComponent(".codex/skills")
        guard fileManager.fileExists(atPath: dir) else { return [] }

        var skills: [Skill] = []
        guard let children = try? fileManager.contentsOfDirectory(atPath: dir) else { return [] }

        for child in children where child != ".system" && !child.hasPrefix(".") {
            let childPath = (dir as NSString).appendingPathComponent(child)
            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: childPath, isDirectory: &isDir), isDir.boolValue else { continue }

            let skillPath = (childPath as NSString).appendingPathComponent("SKILL.md")
            if let skill = parseSkillMD(at: skillPath, source: .codexCLI(.user), checkAgentYaml: true, parentDir: childPath) {
                skills.append(skill)
            }
        }

        return skills
    }

    // MARK: - Helpers

    private func scanDirectChildren(dir: String, source: SkillSource, checkAgentYaml: Bool = false) -> [Skill] {
        guard fileManager.fileExists(atPath: dir) else { return [] }
        guard let children = try? fileManager.contentsOfDirectory(atPath: dir) else { return [] }

        var skills: [Skill] = []
        for child in children where !child.hasPrefix(".") {
            let childPath = (dir as NSString).appendingPathComponent(child)
            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: childPath, isDirectory: &isDir), isDir.boolValue else { continue }

            let skillPath = (childPath as NSString).appendingPathComponent("SKILL.md")
            if let skill = parseSkillMD(at: skillPath, source: source, checkAgentYaml: checkAgentYaml, parentDir: childPath) {
                skills.append(skill)
            }
        }
        return skills
    }

    private func parseSkillMD(at path: String, source: SkillSource, checkAgentYaml: Bool = false, parentDir: String? = nil) -> Skill? {
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        guard let parsed = FrontmatterParser.parse(content: content) else {
            // If no valid frontmatter, still create a skill with folder name
            let folderName = URL(fileURLWithPath: path).deletingLastPathComponent().lastPathComponent
            return Skill(name: folderName, description: "", source: source, path: path)
        }

        var name = parsed.name
        var description = parsed.description

        // For Codex skills, check agents/openai.yaml for better display info
        if checkAgentYaml, let dir = parentDir {
            let agentPath = (dir as NSString).appendingPathComponent("agents/openai.yaml")
            if let agentContent = try? String(contentsOfFile: agentPath, encoding: .utf8) {
                let agent = FrontmatterParser.parseOpenAIAgent(content: agentContent)
                if let displayName = agent.displayName, !displayName.isEmpty {
                    name = displayName
                }
                if let shortDesc = agent.shortDescription, !shortDesc.isEmpty, description.isEmpty {
                    description = shortDesc
                }
            }
        }

        // Fallback name to folder name
        if name.isEmpty {
            name = URL(fileURLWithPath: path).deletingLastPathComponent().lastPathComponent
        }

        // File metadata
        let skillDir = (path as NSString).deletingLastPathComponent
        let lastModified = (try? fileManager.attributesOfItem(atPath: path))?[.modificationDate] as? Date
        let allItems = (try? fileManager.contentsOfDirectory(atPath: skillDir))?
            .filter { !$0.hasPrefix(".") }
            .sorted() ?? []
        var directories: Set<String> = []
        var dirContents: [String: [String]] = [:]
        for item in allItems {
            var isDir: ObjCBool = false
            let itemPath = (skillDir as NSString).appendingPathComponent(item)
            if fileManager.fileExists(atPath: itemPath, isDirectory: &isDir), isDir.boolValue {
                directories.insert(item)
                dirContents[item] = (try? fileManager.contentsOfDirectory(atPath: itemPath))?
                    .filter { !$0.hasPrefix(".") }
                    .sorted() ?? []
            }
        }

        return Skill(name: name, description: description, source: source, path: path, version: parsed.version, body: parsed.body, lastModified: lastModified, folderContents: allItems, folderDirectories: directories, directoryContents: dirContents)
    }
}
