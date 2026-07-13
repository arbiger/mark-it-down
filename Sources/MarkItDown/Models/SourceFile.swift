import Foundation

struct SourceFile: Identifiable, Equatable {
    let id: UUID
    let sourceURL: URL
    let outputURL: URL
    var status: ConversionStatus
    var errorMessage: String?

    init(
        id: UUID = UUID(),
        sourceURL: URL,
        outputURL: URL,
        status: ConversionStatus = .pending,
        errorMessage: String? = nil
    ) {
        self.id = id
        self.sourceURL = sourceURL
        self.outputURL = outputURL
        self.status = status
        self.errorMessage = errorMessage
    }
}