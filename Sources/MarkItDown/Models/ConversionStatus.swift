import Foundation

enum ConversionStatus: Equatable, Sendable {
    case pending
    case running
    case done
    case failed(String)
    case cancelled
}
