# SwiftUI Private Contacts

This native iOS and Mac Catalyst sample stores a private contact directory in an encrypted SQLite database. It consumes the published `SQLiteEncrypted` Swift package, validates SEE activation, opens the database through the checked keyed initializer, and uses the ordinary SQLite.swift API for searchable CRUD.

## Prerequisites

- macOS with Xcode 16.3 or later (Swift tools 6.1)
- iOS 17 or later, or Mac Catalyst
- A SQLite.Encrypted activation key for the selected platform

Free fully-featured demo keys are available from
[sqlite.sourcegear.com](https://sqlite.sourcegear.com/#evaluation).

## Run the app

1. Open `PrivateContacts.xcodeproj` in Xcode.
2. Wait for Swift Package Manager to resolve `SQLiteEncrypted` from:

   ```text
   https://packages.sourcegear.com/swift/publisher/SQLiteEncrypted.git
   ```

3. Select an iOS simulator or **My Mac (Designed for iPad)** / Mac Catalyst destination.
4. Run the `PrivateContacts` scheme.
5. Paste the raw activation key and choose a database passphrase.

The activation key must be the raw value accepted by `activateSEE(activationKey:)`; do not add the `see-` PRAGMA prefix. You may also define `SQLITE_ENCRYPTED_ACTIVATION_KEY` in the scheme's Run environment variables to prefill the field.

An invalid activation attempt poisons SEE activation for that process. The sample reports a clear error and asks you to restart the app after correcting the key.

## Implementation

- `EncryptedContactStore.swift` owns activation validation, keyed open, schema creation, and every query.
- `ContentView.swift` contains the SwiftUI unlock, search, list, and editor screens.
- `Contact.swift` is the UI model.

Activation is verified with a disposable encrypted database before the application database is opened. The real database uses `Connection(path, key:)`, followed immediately by a `sqlite_master` read so a wrong passphrase fails before application queries run.

The database passphrase is retained only in memory. A production application should derive or store it using a design appropriate to its threat model, such as Keychain-protected key material.

