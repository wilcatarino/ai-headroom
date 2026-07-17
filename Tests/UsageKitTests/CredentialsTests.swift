import UsageKit

func testPackageBuilds() {
    T.equal(UsageKit.marker, "usagekit")
}

func testCredentials() {
    T.equal(planLabel(subscriptionType: "max", rateLimitTier: "default_claude_max_20x"), "Max (20x)")
    T.equal(planLabel(subscriptionType: "pro", rateLimitTier: nil), "Pro")
    T.equal(planLabel(subscriptionType: nil, rateLimitTier: nil), "Claude Code")
}
