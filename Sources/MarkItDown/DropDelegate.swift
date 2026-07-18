import AppKit
import UniformTypeIdentifiers
import SwiftUI

private final class DroppedURLBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [URL] = []

    func append(_ url: URL) {
        lock.lock()
        storage.append(url)
        lock.unlock()
    }

    func snapshot() -> [URL] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}

@MainActor
final class ItemDropDelegate: NSObject {
    var onItems: (([URL]) -> Void)?

    /// Preserve the exact dropped selection. FileScanner expands directories later,
    /// while explicitly selected files are converted without scanning their siblings.
    func acceptDroppedItems(_ items: [URL]) {
        let uniqueItems = Array(Set(items.map(\.standardizedFileURL)))
            .sorted { $0.path < $1.path }
        guard !uniqueItems.isEmpty else { return }
        onItems?(uniqueItems)
    }

    /// ItemProvider-driven entry point for SwiftUI's `.onDrop`.
    func validateAndExtract(from providers: [NSItemProvider]) {
        guard !providers.isEmpty else { return }
        let group = DispatchGroup()
        let urls = DroppedURLBuffer()

        for provider in providers {
            guard provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) else {
                continue
            }
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                defer { group.leave() }
                var url: URL?
                if let data = item as? Data {
                    url = URL(dataRepresentation: data, relativeTo: nil)
                } else if let direct = item as? URL {
                    url = direct
                }
                if let resolved = url {
                    urls.append(resolved)
                }
            }
        }

        group.notify(queue: .main) { [weak self] in
            self?.acceptDroppedItems(urls.snapshot())
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
