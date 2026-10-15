import SwiftUI

// MARK: - The Desk server: address and bearer token (IP-172)

struct ConnectionSheet: View {
    @Environment(DeskConnection.self) private var connection
    @Environment(\.dismiss) private var dismiss

    @State private var address = ""
    @State private var token = ""

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
                    Text("The token is the password of the 1Password item infra.desk-api. It is kept in this phone's Keychain and sent only to this address.")
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
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        connection.save(address: address, token: token)
                        dismiss()
                    }
                    .disabled(URL(string: address) == nil || (!connection.hasToken && token.isEmpty))
                }
            }
            .onAppear { address = connection.address }
        }
    }
}
