import Foundation

public struct KeychainStore: CredentialsStoring {
    private let keychain: Keychain
    public init(keychain: Keychain = Keychain(service: "Claude Code-credentials")) {
        self.keychain = keychain
    }

    public func load() throws -> Credentials? {
        guard let data = try keychain.readData() else { return nil }
        return try CredentialsBlob.parse(data)
    }

    public func saveRefreshedTokens(_ t: RefreshedTokens) throws {
        guard let data = try keychain.readData() else { throw TokenError.notLoggedIn }
        let updated = try CredentialsBlob.writingRefreshedTokens(
            into: data, accessToken: t.accessToken, refreshToken: t.refreshToken,
            expiresAtMillis: t.expiresAtMillis)
        try keychain.writeData(updated)
    }
}
