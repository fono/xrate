import Foundation

struct Currency: Codable, Hashable, Identifiable, Sendable {
    let code: String
    let name: String

    var id: String { code }
}
