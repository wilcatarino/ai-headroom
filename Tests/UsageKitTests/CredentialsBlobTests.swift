import Foundation
import UsageKit

func testCredentialsBlob() {
    // parse
    let creds = try! CredentialsBlob.parse(T.fixtureData("credentials-blob"))
    T.equal(creds.accessToken, "sk-ant-oat01-OLD")
    T.equal(creds.refreshToken, "sk-ant-ort01-OLD")
    T.equal(creds.expiresAtMillis, 1000)
    T.equal(creds.subscriptionType, "max")
    T.equal(creds.rateLimitTier, "default_claude_max_20x")

    // write preserves other keys
    let original = T.fixtureData("credentials-blob")
    let updated = try! CredentialsBlob.writingRefreshedTokens(
        into: original, accessToken: "NEW-AT", refreshToken: "NEW-RT", expiresAtMillis: 2000)
    let obj = try! JSONSerialization.jsonObject(with: updated) as! [String: Any]
    let oauth = obj["claudeAiOauth"] as! [String: Any]
    T.equal(oauth["accessToken"] as? String, "NEW-AT")
    T.equal(oauth["refreshToken"] as? String, "NEW-RT")
    T.equal(oauth["expiresAt"] as? Int, 2000)
    T.equal(oauth["subscriptionType"] as? String, "max")
    let mcp = obj["mcpOAuth"] as! [String: Any]
    T.expect(mcp["linear-mcp|abc"] != nil, "mcpOAuth preserved")

    // malformed throws
    var threw = false
    do { _ = try CredentialsBlob.parse(Data("not json".utf8)) } catch { threw = true }
    T.expect(threw, "malformed input throws")
}
