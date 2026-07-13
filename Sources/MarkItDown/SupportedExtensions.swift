import Foundation

enum SupportedExtensions {
    static let all: Set<String> = [
        "pdf", "docx", "pptx", "xlsx", "xls",
        "html", "htm", "txt", "md", "rtf",
        "epub", "csv", "json", "xml",
        "png", "jpg", "jpeg", "gif", "webp",
        "mp3", "wav", "m4a", "zip"
    ]

    static func isSupported(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        guard !ext.isEmpty else { return false }
        return all.contains(ext)
    }
}