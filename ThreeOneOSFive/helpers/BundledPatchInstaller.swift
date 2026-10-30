import Foundation

/// Copies the patch packages shipped with the app into the user's patch library.
enum BundledPatchInstaller {
    private static let resourceFolderName = "BundledPatches"

    static func installIfNeeded(fileManager: FileManager = .default) {
        guard let resourceFolder = Bundle.main.url(
            forResource: resourceFolderName,
            withExtension: nil,
            subdirectory: nil
        ) else {
            log("bundled patches: resource folder not found")
            return
        }

        do {
            let destinationRoot = try PatchProjectLibrary.packageRootURL(fileManager: fileManager)
            let existingIDs = Set(PatchProjectLibrary.load(fileManager: fileManager).map(\.id))
            let packages = try fileManager.contentsOfDirectory(
                at: resourceFolder,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )

            for sourceURL in packages where sourceURL.pathExtension.lowercased() == "3105" {
                let data = try Data(contentsOf: sourceURL, options: .mappedIfSafe)
                let summary = try PatchPackageCodec.inspect(data)
                guard !existingIDs.contains(summary.packageID) else { continue }

                let destination = uniqueDestination(
                    named: sourceURL.lastPathComponent,
                    in: destinationRoot,
                    fileManager: fileManager
                )
                try data.write(to: destination, options: [.atomic, .completeFileProtection])
            }
        } catch {
            log("bundled patches: installation failed: \(error)")
        }
    }

    private static func uniqueDestination(
        named name: String,
        in root: URL,
        fileManager: FileManager
    ) -> URL {
        let base = root.appendingPathComponent(name)
        guard fileManager.fileExists(atPath: base.path) else { return base }

        let stem = base.deletingPathExtension().lastPathComponent
        let ext = base.pathExtension
        var suffix = 2
        while true {
            let candidate = root
                .appendingPathComponent("\(stem)-\(suffix)")
                .appendingPathExtension(ext)
            if !fileManager.fileExists(atPath: candidate.path) { return candidate }
            suffix += 1
        }
    }
}
