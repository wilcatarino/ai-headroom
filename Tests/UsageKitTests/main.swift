import Foundation

// Registry of all test functions. Add new ones here as tasks land.
func runAllTests() async {
    testPackageBuilds()
}

await runAllTests()

print("")
if T.failures == 0 {
    print("✓ All \(T.passed) checks passed")
    exit(0)
} else {
    print("✗ \(T.failures) failed, \(T.passed) passed")
    exit(1)
}
