import Foundation

struct PluginScanner {
    private let fileManager = FileManager.default
    private let home = FileManager.default.homeDirectoryForCurrentUser.path

    func scanInstalledPlugins() -> [Plugin] {
        let cacheDir = (home as NSString).appendingPathComponent(".codex/plugins/cache")
        guard fileManager.fileExists(atPath: cacheDir) else { return [] }
        guard let enumerator = fileManager.enumerator(atPath: cacheDir) else { return [] }

        var pluginsByIdentifier: [String: Plugin] = [:]

        while let relativePath = enumerator.nextObject() as? String {
            guard (relativePath as NSString).lastPathComponent == "plugin.json" else { continue }

            let manifestDir = (relativePath as NSString).deletingLastPathComponent
            guard (manifestDir as NSString).lastPathComponent == ".codex-plugin" else { continue }

            let fullPath = (cacheDir as NSString).appendingPathComponent(relativePath)
            guard let plugin = parsePluginManifest(at: fullPath, cacheRoot: cacheDir) else { continue }

            let key = "\(plugin.publisher ?? "local")::\(plugin.name.lowercased())"
            if let existing = pluginsByIdentifier[key] {
                let pluginDate = plugin.lastModified ?? .distantPast
                let existingDate = existing.lastModified ?? .distantPast
                if pluginDate >= existingDate {
                    pluginsByIdentifier[key] = plugin
                }
            } else {
                pluginsByIdentifier[key] = plugin
            }
        }

        return pluginsByIdentifier.values.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    private func parsePluginManifest(at manifestPath: String, cacheRoot: String) -> Plugin? {
        guard let data = fileManager.contents(atPath: manifestPath) else { return nil }
        guard let manifest = try? JSONDecoder().decode(CodexPluginManifest.self, from: data) else { return nil }

        let rootPath = URL(fileURLWithPath: manifestPath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .path

        let lastModified = (try? fileManager.attributesOfItem(atPath: manifestPath))?[.modificationDate] as? Date

        return Plugin(
            name: manifest.name,
            displayNameOverride: manifest.interface?.displayName,
            shortDescriptionOverride: manifest.interface?.shortDescription,
            description: firstNonEmpty(
                manifest.interface?.longDescription,
                manifest.description,
                manifest.interface?.shortDescription
            ),
            version: manifest.version,
            path: (rootPath as NSString).standardizingPath,
            manifestPath: (manifestPath as NSString).standardizingPath,
            publisher: publisherName(for: rootPath, cacheRoot: cacheRoot),
            authorName: firstNonEmpty(manifest.author?.name, manifest.interface?.developerName),
            homepage: manifest.homepage,
            repository: manifest.repository,
            keywords: manifest.keywords ?? [],
            capabilities: manifest.interface?.capabilities ?? [],
            defaultPrompt: manifest.interface?.defaultPrompt,
            lastModified: lastModified
        )
    }

    private func publisherName(for pluginRoot: String, cacheRoot: String) -> String? {
        let standardizedRoot = (pluginRoot as NSString).standardizingPath
        let standardizedCacheRoot = (cacheRoot as NSString).standardizingPath
        let prefix = standardizedCacheRoot + "/"

        guard standardizedRoot.hasPrefix(prefix) else { return nil }
        let relativePath = String(standardizedRoot.dropFirst(prefix.count))
        return relativePath.components(separatedBy: "/").first
    }

    private func firstNonEmpty(_ candidates: String?...) -> String {
        for candidate in candidates {
            let trimmed = candidate?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !trimmed.isEmpty {
                return trimmed
            }
        }
        return ""
    }
}

private struct CodexPluginManifest: Decodable {
    struct Author: Decodable {
        let name: String?
    }

    struct Interface: Decodable {
        let displayName: String?
        let shortDescription: String?
        let longDescription: String?
        let developerName: String?
        let capabilities: [String]?
        let defaultPrompt: String?
    }

    let name: String
    let version: String?
    let description: String?
    let author: Author?
    let homepage: String?
    let repository: String?
    let keywords: [String]?
    let interface: Interface?
}
