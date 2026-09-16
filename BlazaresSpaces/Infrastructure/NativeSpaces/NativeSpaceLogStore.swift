import Foundation

/// Small append-only diagnostic sink for native Space operations. The file is
/// intentionally plain text so it can be inspected after the app terminates.
nonisolated struct NativeSpaceLogStore: Sendable {
    let fileURL: URL

    nonisolated init(fileManager: FileManager = .default) {
        let baseURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        self.fileURL = baseURL
            .appendingPathComponent("BlazaresSpaces", isDirectory: true)
            .appendingPathComponent("native-spaces.log", isDirectory: false)
    }

    nonisolated func append(_ line: String) {
        let directoryURL = fileURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            let data = Data((line + "\n").utf8)
            if FileManager.default.fileExists(atPath: fileURL.path),
               let handle = try? FileHandle(forWritingTo: fileURL) {
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
                try handle.close()
            } else {
                try data.write(to: fileURL, options: .atomic)
            }
        } catch {
            // Diagnostics must never affect the app's operation path.
        }
    }
}
