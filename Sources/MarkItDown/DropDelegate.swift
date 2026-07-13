import AppKit
import UniformTypeIdentifiers
import SwiftUI

final class ItemDropDelegate: NSObject {
    var onRoot: ((URL) -> Void)?

    /// Accept a folder or file (or mix of multiple items) and resolve them to a single
    /// root folder URL. Recursively walks the folder via FileScanner downstream.
    /// - Folder drop → that folder is the root
    /// - File drop → the file's parent folder is the root
    /// - Multi-file drop → the common parent is the root
    func acceptDroppedItems(_ items: [URL]) {
        guard !items.isEmpty else { return }
        let fm = FileManager.default

        let root: URL?
        if let firstFolder = items.first(where: {
            var isDir: ObjCBool = false
            return fm.fileExists(atPath: $0.path, isDirectory: &isDir) && isDir.boolValue
        }) {
            // A folder was dropped — use it.
            root = firstFolder
        } else {
            // Files only — use common parent (or first file's parent if mixed).
            let parents = Set(items.map { $0.deletingLastPathComponent() })
            root = parents.first
        }
        guard let root = root else { return }

        DispatchQueue.main.async { [weak self] in
            self?.onRoot?(root)
        }
    }

    /// ItemProvider-driven entry point for SwiftUI's `.onDrop`.
    func validateAndExtract(from providers: [NSItemProvider]) {
        guard !providers.isEmpty else { return }
        let group = DispatchGroup()
        var urls: [URL] = []
        let lock = NSLock()
        let group_lock = NSLock()
        var remaining = providers.count

        for provider in providers {
            guard provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) else {
                group_lock.lock()
                remaining -= 1
                group_lock.unlock()
                continue
            }
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                defer {
                    group.leave()
                    group_lock.lock()
                    remaining -= 1
                    group_lock.unlock()
                }
                var url: URL?
                if let data = item as? Data {
                    url = URL(dataRepresentation: data, relativeTo: nil)
                } else if let direct = item as? URL {
                    url = direct
                }
                if let resolved = url {
                    lock.lock()
                    urls.append(resolved)
                    lock.unlock()
                }
            }
        }

        group.notify(queue: .main) { [weak self] in
            self?.acceptDroppedItems(urls)
        }
    }
}

// SwiftUI bridge
extension ItemDropDelegate: DropDelegate {
    func performDrop(info: DropInfo) -> Bool {
        validateAndExtract(from: info.itemProviders(for: [UTType.fileURL]))
        return true
    }

    func validateDrop(info: DropInfo) -> Bool {
        info.itemProviders(for: [UTType.fileURL]).contains { $0.canLoadObject(ofClass: URL.self) }
    }
}