import SwiftUI

struct ContentView: View {
    @StateObject private var store = EncryptedContactStore()

    var body: some View {
        Group {
            if store.isOpen {
                ContactsView(store: store)
            } else {
                UnlockView(store: store)
            }
        }
        .tint(.indigo)
    }
}

private struct UnlockView: View {
    @ObservedObject var store: EncryptedContactStore
    @State private var activationKey = ProcessInfo.processInfo.environment[
        "SQLITE_ENCRYPTED_ACTIVATION_KEY"
    ] ?? ""
    @State private var databasePassphrase = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("Activation key", text: $activationKey)
                        .textContentType(.password)
                    SecureField("Database passphrase", text: $databasePassphrase)
                        .textContentType(.password)
                } header: {
                    Text("Open encrypted contacts")
                } footer: {
                    Text("The database passphrase remains in memory only while the app is running.")
                }

                if let errorMessage = store.errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }

                Button("Open encrypted contacts") {
                    store.open(
                        activationKey: activationKey,
                        databasePassphrase: databasePassphrase
                    )
                    if store.isOpen {
                        databasePassphrase = ""
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(activationKey.isEmpty || databasePassphrase.isEmpty)
            }
            .navigationTitle("Private Contacts")
        }
    }
}

private struct EditorState: Identifiable {
    let id = UUID()
    let contact: Contact?
}

private struct ContactsView: View {
    @ObservedObject var store: EncryptedContactStore
    @State private var search = ""
    @State private var editor: EditorState?
    @State private var operationError: String?

    var body: some View {
        NavigationStack {
            List(store.contacts) { contact in
                Button {
                    editor = EditorState(contact: contact)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(contact.name).font(.headline)
                        if !contact.phone.isEmpty {
                            Text(contact.phone).foregroundStyle(.secondary)
                        }
                        if !contact.email.isEmpty {
                            Text(contact.email).foregroundStyle(.secondary)
                        }
                    }
                }
                .buttonStyle(.plain)
                .swipeActions {
                    Button(role: .destructive) {
                        perform { try store.delete(contact) }
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
            .overlay {
                if store.contacts.isEmpty {
                    ContentUnavailableView(
                        search.isEmpty ? "No contacts" : "No matches",
                        systemImage: "person.crop.circle.badge.questionmark",
                        description: Text(search.isEmpty
                            ? "Add a contact to the encrypted database."
                            : "Try a different search.")
                    )
                }
            }
            .navigationTitle("Private Contacts")
            .searchable(text: $search, prompt: "Name, phone, email, or notes")
            .onChange(of: search) { _, value in
                perform { try store.reload(search: value) }
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        editor = EditorState(contact: nil)
                    } label: {
                        Label("Add contact", systemImage: "plus")
                    }
                }
            }
            .sheet(item: $editor) { state in
                ContactEditor(contact: state.contact) { name, phone, email, notes in
                    try store.save(
                        contact: state.contact,
                        name: name,
                        phone: phone,
                        email: email,
                        notes: notes
                    )
                    if !search.isEmpty {
                        try store.reload(search: search)
                    }
                }
            }
            .alert("Database error", isPresented: Binding(
                get: { operationError != nil },
                set: { if !$0 { operationError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(operationError ?? "")
            }
        }
    }

    private func perform(_ action: () throws -> Void) {
        do {
            try action()
        } catch {
            operationError = String(describing: error)
        }
    }
}

private struct ContactEditor: View {
    @Environment(\.dismiss) private var dismiss
    let contact: Contact?
    let save: (String, String, String, String) throws -> Void
    @State private var name: String
    @State private var phone: String
    @State private var email: String
    @State private var notes: String
    @State private var errorMessage: String?

    init(contact: Contact?, save: @escaping (String, String, String, String) throws -> Void) {
        self.contact = contact
        self.save = save
        _name = State(initialValue: contact?.name ?? "")
        _phone = State(initialValue: contact?.phone ?? "")
        _email = State(initialValue: contact?.email ?? "")
        _notes = State(initialValue: contact?.notes ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                TextField("Phone", text: $phone)
                    .keyboardType(.phonePad)
                TextField("Email", text: $email)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                TextField("Private notes", text: $notes, axis: .vertical)
                    .lineLimit(3...8)
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
            .navigationTitle(contact == nil ? "New Contact" : "Edit Contact")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        do {
                            try save(name, phone, email, notes)
                            dismiss()
                        } catch {
                            errorMessage = String(describing: error)
                        }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

