import Foundation
import Testing

@Suite("Architecture fitness")
struct ArchitectureFitnessTests {
    @Test("Domain stays independent from UI, AX, and persistence adapters")
    func domainDependencies() throws {
        let sources = try swiftSources(in: try requiredSourceDirectory(named: "Domain"))

        for source in sources {
            let code = try executableSwift(at: source)
            for module in ["SwiftUI", "AppKit", "ApplicationServices"] {
                #expect(!imports(module, in: code), "Domain source \(source.lastPathComponent) imports \(module)")
            }
            for symbol in ["AXUIElement", "UserDefaults"] {
                #expect(!containsIdentifier(symbol, in: code), "Domain source \(source.lastPathComponent) references \(symbol)")
            }
        }
    }

    @Test("UI sends intents instead of performing Accessibility mutations")
    func uiDependencies() throws {
        for source in try uiSwiftSources() {
            let code = try executableSwift(at: source)
            #expect(!imports("ApplicationServices", in: code), "UI source \(source.lastPathComponent) imports ApplicationServices")
            for symbol in [
                "AXUIElement",
                "AXExternalWindowController",
                "AXWindowController",
                "WorkspaceConfigurationStore",
                "GlobalShortcutConfigurationStore",
                "UserDefaults"
            ] {
                #expect(!containsIdentifier(symbol, in: code), "UI source \(source.lastPathComponent) references \(symbol)")
            }
        }
    }

    private func requiredSourceDirectory(named name: String) throws -> URL {
        let directory = applicationSources.appendingPathComponent(name, isDirectory: true)
        guard FileManager.default.fileExists(atPath: directory.path) else {
            throw ArchitectureFitnessError.missingSourceDirectory(directory.path)
        }
        return directory
    }

    /// During the folder migration, views still live in several legacy folders.
    /// Prefer the canonical UI folder once present; otherwise inspect every source
    /// that actually imports SwiftUI, rather than silently skipping the boundary.
    private func uiSwiftSources() throws -> [URL] {
        let uiDirectory = applicationSources.appendingPathComponent("UI", isDirectory: true)
        if FileManager.default.fileExists(atPath: uiDirectory.path) {
            return try swiftSources(in: uiDirectory)
        }
        return try swiftSources(in: applicationSources).filter {
            try imports("SwiftUI", in: executableSwift(at: $0))
        }
    }

    private var applicationSources: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("BlazaresSpaces", isDirectory: true)
    }

    private func swiftSources(in directory: URL) throws -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            throw ArchitectureFitnessError.cannotEnumerate(directory.path)
        }

        return try enumerator.compactMap { item in
            guard let url = item as? URL, url.pathExtension == "swift" else { return nil }
            let values = try url.resourceValues(forKeys: [.isRegularFileKey])
            return values.isRegularFile == true ? url : nil
        }
        .sorted { $0.path < $1.path }
    }

    private func executableSwift(at url: URL) throws -> String {
        stripCommentsAndStrings(from: try String(contentsOf: url, encoding: .utf8))
    }

    private func imports(_ module: String, in code: String) -> Bool {
        code.split(separator: "\n").contains { line in
            let fields = line.split(whereSeparator: { $0.isWhitespace })
            guard let index = fields.firstIndex(of: "import"), fields.indices.contains(index + 1) else {
                return false
            }
            return fields[index + 1].split(separator: ".").first == Substring(module)
        }
    }

    private func containsIdentifier(_ identifier: String, in code: String) -> Bool {
        code.split { !$0.isLetter && !$0.isNumber && $0 != "_" }.contains(Substring(identifier))
    }

    /// Preserve newlines but remove nested comments and string contents, so names
    /// shown in documentation or UI copy do not trigger dependency violations.
    private func stripCommentsAndStrings(from source: String) -> String {
        enum State { case code, lineComment, blockComment(Int), string }
        let characters = Array(source)
        var output = ""
        var state = State.code
        var index = 0

        while index < characters.count {
            let current = characters[index]
            let next = index + 1 < characters.count ? characters[index + 1] : nil

            switch state {
            case .code:
                if current == "/", next == "/" {
                    state = .lineComment
                    index += 2
                } else if current == "/", next == "*" {
                    state = .blockComment(1)
                    index += 2
                } else if current == "\"" {
                    state = .string
                    output.append(" ")
                    index += 1
                } else {
                    output.append(current)
                    index += 1
                }
            case .lineComment:
                if current == "\n" {
                    output.append("\n")
                    state = .code
                }
                index += 1
            case let .blockComment(depth):
                if current == "/", next == "*" {
                    state = .blockComment(depth + 1)
                    index += 2
                } else if current == "*", next == "/" {
                    state = depth == 1 ? .code : .blockComment(depth - 1)
                    index += 2
                } else {
                    if current == "\n" { output.append("\n") }
                    index += 1
                }
            case .string:
                if current == "\\" {
                    index += min(2, characters.count - index)
                } else if current == "\"" {
                    state = .code
                    index += 1
                } else {
                    if current == "\n" { output.append("\n") }
                    index += 1
                }
            }
        }
        return output
    }
}

private enum ArchitectureFitnessError: Error {
    case missingSourceDirectory(String)
    case cannotEnumerate(String)
}
