import Foundation

struct Contact: Identifiable, Equatable {
    let id: Int64
    var name: String
    var phone: String
    var email: String
    var notes: String
    var updatedAt: String
}

