import Foundation
import Security

// MARK: - The Desk API (IP-172): one server, one bearer token
//
// `monad_knowledge/desk_api` on desk.monad.dubec.dev. Banks and receipts come
// from it, locked Desk sessions go to it, and the Library reads papers and
// claims through it. The token lives in the Keychain, the address in
// UserDefaults. Without a token every call throws `.notConnected` and the
// app keeps working from what it bundled and cached.

enum DeskAPIError: LocalizedError, Equatable {
    case notConnected
    case unauthorized
    case notFound
    case conflict(String)
    case rejected(String)
    case server(Int)
    case offline(String)

    var errorDescription: String? {
        switch self {
        case .notConnected: "No Desk server is set up. Add the address and token in Curate."
        case .unauthorized: "The server refused the token."
        case .notFound: "The server has no such record."
        case .conflict(let why): why
        case .rejected(let why): why
        case .server(let code): "The server answered \(code)."
        case .offline(let why): "The server could not be reached: \(why)"
        }
    }
}

/// What the server says about a sent session.
enum ReceiptState: Equatable {
    case receipt(Data)
    case rejected(String)
    case pending
    case unknown
}

@MainActor
@Observable
final class DeskConnection {
    static let defaultAddress = "https://desk.monad.dubec.dev"
    private static let addressKey = "desk.api.address"
    private static let keychainService = "monad-defense.desk-api"

    var address: String
    private(set) var hasToken: Bool
    /// The last reachability answer, for the status row. Nil until a call ran.
    private(set) var lastProblem: String?

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
        address = UserDefaults.standard.string(forKey: Self.addressKey) ?? Self.defaultAddress
        hasToken = Self.readToken() != nil
    }

    var isConfigured: Bool { hasToken && URL(string: address) != nil }

    func save(address: String, token: String) {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        self.address = trimmed.hasSuffix("/") ? String(trimmed.dropLast()) : trimmed
        UserDefaults.standard.set(self.address, forKey: Self.addressKey)
        let t = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty { Self.writeToken(t) }
        hasToken = Self.readToken() != nil
    }

    func forget() {
        Self.deleteToken()
        hasToken = false
    }

    // MARK: Calls

    func get(_ path: String, query: [String: String] = [:]) async throws -> Data {
        try await send(request(path, query: query))
    }

    func decode<T: Decodable>(_ type: T.Type, _ path: String, query: [String: String] = [:]) async throws -> T {
        try JSONDecoder().decode(T.self, from: try await get(path, query: query))
    }

    /// Send a locked session. A second send of the same bytes is fine.
    func sendExport(_ data: Data) async throws {
        var req = try request("/api/exports")
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = data
        _ = try await send(req)
    }

    func receipt(sessionID: String) async throws -> ReceiptState {
        let req = try request("/api/receipts/\(sessionID)")
        let (data, response) = try await perform(req)
        switch response.statusCode {
        case 200: return .receipt(data)
        case 422:
            let errors = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["errors"] as? [String]
            return .rejected(errors?.joined(separator: "\n") ?? "The vault importer refused this session.")
        case 404:
            let status = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["status"] as? String
            return status == "pending" ? .pending : .unknown
        case 401: throw DeskAPIError.unauthorized
        default: throw DeskAPIError.server(response.statusCode)
        }
    }

    // MARK: Plumbing

    private func request(_ path: String, query: [String: String] = [:]) throws -> URLRequest {
        guard let token = Self.readToken(), var components = URLComponents(string: address + path) else {
            throw DeskAPIError.notConnected
        }
        if !query.isEmpty { components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) } }
        guard let url = components.url else { throw DeskAPIError.notConnected }
        var req = URLRequest(url: url, timeoutInterval: 30)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return req
    }

    private func send(_ req: URLRequest) async throws -> Data {
        let (data, response) = try await perform(req)
        switch response.statusCode {
        case 200..<300: return data
        case 401: throw DeskAPIError.unauthorized
        case 404: throw DeskAPIError.notFound
        case 409: throw DeskAPIError.conflict(Self.detail(data) ?? "The server already holds other content for this.")
        case 422: throw DeskAPIError.rejected(Self.detail(data) ?? "The server refused the request.")
        default: throw DeskAPIError.server(response.statusCode)
        }
    }

    private func perform(_ req: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await session.data(for: req)
            guard let http = response as? HTTPURLResponse else { throw DeskAPIError.server(0) }
            lastProblem = http.statusCode == 401 ? DeskAPIError.unauthorized.errorDescription : nil
            return (data, http)
        } catch let error as DeskAPIError {
            throw error
        } catch {
            lastProblem = error.localizedDescription
            throw DeskAPIError.offline(error.localizedDescription)
        }
    }

    private static func detail(_ data: Data) -> String? {
        (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["detail"] as? String
    }

    // MARK: Keychain

    private static func query() -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: keychainService]
    }

    private static func readToken() -> String? {
        var q = query()
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func writeToken(_ token: String) {
        deleteToken()
        var q = query()
        q[kSecValueData as String] = Data(token.utf8)
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(q as CFDictionary, nil)
    }

    private static func deleteToken() {
        SecItemDelete(query() as CFDictionary)
    }
}
