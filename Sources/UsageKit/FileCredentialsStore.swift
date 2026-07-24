import Foundation

/// Reads Claude Code credentials from a JSON file (the same `claudeAiOauth`
/// blob the keychain holds). This is where Claude Code keeps credentials when
/// the keychain is not used (Linux, headless/CI, or keychain disabled), so it
/// serves as a fallback source for devs who do not have the keychain item.
/// Unlike the keychain, reading a file raises no authorization prompt.
public struct FileCredentialsStore: CredentialsStoring {
    private let path: String

    public init(path: String) { self.path = path }

    /// The path Claude Code uses: `$CLAUDE_CONFIG_DIR/.credentials.json`,
    /// falling back to `~/.claude/.credentials.json`.
    public static func defaultPath(environment: [String: String] = ProcessInfo.processInfo.environment,
                                   home: String = NSHomeDirectory()) -> String {
        let base = environment["CLAUDE_CONFIG_DIR"].flatMap { $0.isEmpty ? nil : $0 }
            ?? (home as NSString).appendingPathComponent(".claude")
        return (base as NSString).appendingPathComponent(".credentials.json")
    }

    public func load() throws -> Credentials? {
        guard let data = try readFile() else { return nil }
        return try CredentialsBlob.parse(data)
    }

    public func saveRefreshedTokens(_ t: RefreshedTokens) throws {
        guard let data = try readFile() else { throw TokenError.notLoggedIn }
        let updated = try CredentialsBlob.writingRefreshedTokens(
            into: data, accessToken: t.accessToken, refreshToken: t.refreshToken,
            expiresAtMillis: t.expiresAtMillis)
        // Capture the current mode first: an atomic write replaces the inode and
        // the new file would otherwise pick up the umask default (0644),
        // widening access to what are secret tokens. Reapply the original mode.
        let mode = try FileManager.default.attributesOfItem(atPath: path)[.posixPermissions]
        try updated.write(to: URL(fileURLWithPath: path), options: .atomic)
        if let mode {
            try FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: path)
        }
    }

    private func readFile() throws -> Data? {
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        return try Data(contentsOf: url)
    }
}
