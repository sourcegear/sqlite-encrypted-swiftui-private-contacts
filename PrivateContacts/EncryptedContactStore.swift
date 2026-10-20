import Combine
import Foundation
import SQLiteEncrypted

@MainActor
final class EncryptedContactStore: ObservableObject {
    enum StoreError: LocalizedError {
        case missingActivationKey
        case prefixedActivationKey
        case activationFailed(String)
        case missingDatabasePassphrase
        case databaseOpenFailed(String)

        var errorDescription: String? {
            switch self {
            case .missingActivationKey:
                return "Enter a SQLite.Encrypted activation key."
            case .prefixedActivationKey:
                return "Pass the raw activation key to activateSEE; remove the see- prefix."
            case .activationFailed(let details):
                return "SEE activation failed. Verify that the activation key is valid for iOS, then restart the app. Details: \(details)"
            case .missingDatabasePassphrase:
                return "Enter a database passphrase."
            case .databaseOpenFailed(let details):
                return "The encrypted contacts database could not be opened. Verify its passphrase. Details: \(details)"
            }
        }
    }

    @Published private(set) var contacts: [Contact] = []
    @Published private(set) var isOpen = false
    @Published var errorMessage: String?

    private let contactsTable = Table("contacts")
    private let id = Expression<Int64>("id")
    private let name = Expression<String>("name")
    private let phone = Expression<String>("phone")
    private let email = Expression<String>("email")
    private let notes = Expression<String>("notes")
    private let updatedAt = Expression<String>("updated_at")
    private var database: Connection?

    func open(activationKey: String, databasePassphrase: String) {
        errorMessage = nil
        do {
            try validateActivation(activationKey.trimmingCharacters(in: .whitespacesAndNewlines))
            let passphrase = databasePassphrase.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !passphrase.isEmpty else {
                throw StoreError.missingDatabasePassphrase
            }

            do {
                let connection = try Connection(databaseURL.path, key: passphrase)
                _ = try connection.scalar("SELECT count(*) FROM sqlite_master")
                try connection.run(contactsTable.create(ifNotExists: true) { table in
                    table.column(id, primaryKey: .autoincrement)
                    table.column(name)
                    table.column(phone)
                    table.column(email)
                    table.column(notes)
                    table.column(updatedAt)
                })
                database = connection
                isOpen = true
                try reload()
            } catch {
                throw StoreError.databaseOpenFailed(String(describing: error))
            }
        } catch {
            errorMessage = (error as? any LocalizedError)?.errorDescription ?? String(describing: error)
        }
    }

    func reload(search: String = "") throws {
        guard let database else { return }
        let term = search.trimmingCharacters(in: .whitespacesAndNewlines)
        let query: Table
        if term.isEmpty {
            query = contactsTable
        } else {
            let pattern = "%\(term)%"
            query = contactsTable.filter(
                name.like(pattern) || phone.like(pattern) || email.like(pattern) || notes.like(pattern)
            )
        }

        contacts = try database.prepare(query.order(updatedAt.desc, id.desc)).map { row in
            Contact(
                id: row[id],
                name: row[name],
                phone: row[phone],
                email: row[email],
                notes: row[notes],
                updatedAt: row[updatedAt]
            )
        }
    }

    func save(contact: Contact?, name contactName: String, phone contactPhone: String,
              email contactEmail: String, notes contactNotes: String) throws {
        guard let database else { return }
        let trimmedName = contactName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        let timestamp = ISO8601DateFormatter().string(from: Date())

        if let contact {
            let record = contactsTable.filter(id == contact.id)
            try database.run(record.update(
                name <- trimmedName,
                phone <- contactPhone.trimmingCharacters(in: .whitespacesAndNewlines),
                email <- contactEmail.trimmingCharacters(in: .whitespacesAndNewlines),
                notes <- contactNotes.trimmingCharacters(in: .whitespacesAndNewlines),
                updatedAt <- timestamp
            ))
        } else {
            try database.run(contactsTable.insert(
                name <- trimmedName,
                phone <- contactPhone.trimmingCharacters(in: .whitespacesAndNewlines),
                email <- contactEmail.trimmingCharacters(in: .whitespacesAndNewlines),
                notes <- contactNotes.trimmingCharacters(in: .whitespacesAndNewlines),
                updatedAt <- timestamp
            ))
        }
        try reload()
    }

    func delete(_ contact: Contact) throws {
        guard let database else { return }
        try database.run(contactsTable.filter(id == contact.id).delete())
        try reload()
    }

    private func validateActivation(_ activationKey: String) throws {
        guard !activationKey.isEmpty else { throw StoreError.missingActivationKey }
        guard !activationKey.hasPrefix("see-") else { throw StoreError.prefixedActivationKey }

        let probeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("sqlite-encrypted-activation-\(UUID().uuidString).db")
        defer { try? FileManager.default.removeItem(at: probeURL) }

        do {
            try activateSEE(activationKey: activationKey)
            let probe = try Connection(probeURL.path, key: "temporary activation validation key")
            _ = try probe.scalar("SELECT count(*) FROM sqlite_master")
        } catch {
            throw StoreError.activationFailed(String(describing: error))
        }
    }

    private var databaseURL: URL {
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        let directory = applicationSupport.appendingPathComponent(
            "SQLiteEncryptedPrivateContacts",
            isDirectory: true
        )
        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory.appendingPathComponent("private-contacts.db")
    }
}

