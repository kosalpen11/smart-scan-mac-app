import Foundation

// MARK: - Results and history

struct RuleResult: Codable, Hashable, Sendable {
    var date: Date
    var succeeded: Bool
    var bytesFreed: Int64
    var itemCount: Int
    var message: String
}
