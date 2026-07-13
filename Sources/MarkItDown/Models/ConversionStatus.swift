import Foundation

enum ConversionStatus: Equatable {
    case pending
    case running
    case done
    case failed(String)
    case cancelled
}
