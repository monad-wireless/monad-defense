import SwiftUI

// MARK: - The Desk server: address and bearer token (IP-172)

struct ConnectionSheet: View {
    @Environment(DeskConnection.self) private var connection
    @Environment(\.dismiss) private var dismiss

    @State private var address = ""
    @State private var token = ""
    @State private var saveFailed = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Address", text: $address)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField(connection.hasToken ? "Token (stored; leave empty to keep)" : "Token", text: $token)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } footer: {
                    Text("The token is the password of the 1Password item infra.desk-api. It is kept in this device's Keychain and sent only to this address.")
                }
                if connection.hasToken {
                    Section {
                        Button("Forget the token", role: .destructive) {
                            connection.forget()
                        }
                    }
                }
            }
            .navigationTitle("Desk server")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        connection.save(address: address, token: token)
                        if !token.isEmpty, !connection.hasToken {
                            // The Keychain refused the write: say so instead of closing.
                            saveFailed = true
                        } else {
                            dismiss()
                        }
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(URL(string: address) == nil || (!connection.hasToken && token.isEmpty))
                }
            }
            .alert("The token was not stored", isPresented: $saveFailed) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("The Keychain refused it. On a Mac this happens when the build is not signed with a team.")
            }
            .onAppear { address = connection.address }
        }
        .frame(minWidth: Platform.isMac ? 460 : nil, minHeight: Platform.isMac ? 300 : nil)
    }
}
