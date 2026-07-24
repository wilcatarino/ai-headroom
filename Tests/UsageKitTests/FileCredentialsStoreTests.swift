import Foundation
import UsageKit

func testFileCredentialsStore() {
    let fm = FileManager.default
    let dir = fm.temporaryDirectory.appendingPathComponent("aiheadroom-filestore-\(getpid())")
    try? fm.removeItem(at: dir)
    try! fm.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: dir) }

    // Absent file loads as nil (not an error).
    let missing = dir.appendingPathComponent("missing.json")
    let absentStore = FileCredentialsStore(path: missing.path)
    T.expect((try! absentStore.load()) == nil, "absent file -> nil")

    // Present file parses via the shared blob format.
    let path = dir.appendingPathComponent(".credentials.json")
    try! fm.copyItem(at: URL(fileURLWithPath: fixturePath()), to: path)
    try! fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path.path)
    let store = FileCredentialsStore(path: path.path)
    let creds = try! store.load()
    T.equal(creds?.accessToken, "sk-ant-oat01-OLD")
    T.equal(creds?.rateLimitTier, "default_claude_max_20x")

    // Save rewrites only the token fields, preserving siblings and 0600 perms.
    try! store.saveRefreshedTokens(RefreshedTokens(
        accessToken: "NEW-AT", refreshToken: "NEW-RT", expiresAtMillis: 2000))
    let reloaded = try! store.load()
    T.equal(reloaded?.accessToken, "NEW-AT")
    T.equal(reloaded?.refreshToken, "NEW-RT")
    T.equal(reloaded?.expiresAtMillis, 2000)
    let obj = try! JSONSerialization.jsonObject(with: Data(contentsOf: path)) as! [String: Any]
    let mcp = obj["mcpOAuth"] as! [String: Any]
    T.expect(mcp["linear-mcp|abc"] != nil, "mcpOAuth preserved on file write")
    let perms = try! fm.attributesOfItem(atPath: path.path)[.posixPermissions] as! NSNumber
    T.equal(perms.int16Value, 0o600, "file stays owner-only after write")

    // Saving to an absent file surfaces notLoggedIn (nothing to update).
    var threw = false
    do {
        try FileCredentialsStore(path: missing.path).saveRefreshedTokens(
            RefreshedTokens(accessToken: "x", refreshToken: "y", expiresAtMillis: 1))
    } catch TokenError.notLoggedIn { threw = true } catch {}
    T.expect(threw, "save to absent file -> notLoggedIn")
}

func testFileCredentialsDefaultPath() {
    // CLAUDE_CONFIG_DIR wins when set.
    T.equal(FileCredentialsStore.defaultPath(environment: ["CLAUDE_CONFIG_DIR": "/cfg"], home: "/Users/x"),
            "/cfg/.credentials.json")
    // Empty CLAUDE_CONFIG_DIR is ignored, falls back to ~/.claude.
    T.equal(FileCredentialsStore.defaultPath(environment: ["CLAUDE_CONFIG_DIR": ""], home: "/Users/x"),
            "/Users/x/.claude/.credentials.json")
    // Unset: ~/.claude/.credentials.json.
    T.equal(FileCredentialsStore.defaultPath(environment: [:], home: "/Users/x"),
            "/Users/x/.claude/.credentials.json")
}

private func fixturePath() -> String {
    Bundle.module.url(forResource: "Fixtures/credentials-blob", withExtension: "json")!.path
}
