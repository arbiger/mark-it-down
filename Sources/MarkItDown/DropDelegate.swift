import AppKit
import UniformTypeIdentifiers
import SwiftUI

final class FolderDropDelegate: NSObject {
    var onFolder: ((URL) -> Void)?

    func validateAndExtract(from providers: [NSItemProvider]) {
        guard let provider = providers.first else { return }
        guard provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) else { return }

        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            var url: URL?
            if let data = item as? Data {
                url = URL(dataRepresentation: data, relativeTo: nil)
            } else if let direct = item as? URL {
                url = direct
            }
            guard let resolved = url else { return }
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: resolved.path, isDirectory: &isDir),
                  isDir.boolValue else { return }

            DispatchQueue.main.async { [weak self] in
                self?.onFolder?(resolved)
            }
        }
    }
}

// SwiftUI bridge: implement the DropDelegate protocol so SwiftUI's `.onDrop` works.
extension FolderDropDelegate: DropDelegate {
    func performDrop(info: DropInfo) -> Bool {
        validateAndExtract(from: info.itemProviders(for: [UTType.fileURL]))
        return true
    }

    func validateDrop(info: DropInfo) -> Bool {
        info.itemProviders(for: [UTType.fileURL]).contains { $0.canLoadObject(ofClass: URL.self) }
    }
}