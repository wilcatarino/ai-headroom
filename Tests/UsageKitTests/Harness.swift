import Foundation

/// Tiny assertion harness so tests run without Xcode (no XCTest/swift-testing).
enum T {
    nonisolated(unsafe) static var failures = 0
    nonisolated(unsafe) static var passed = 0

    static func expect(_ cond: Bool, _ msg: String, line: UInt = #line) {
        if cond { passed += 1 }
        else { failures += 1; print("  ✗ FAIL [\(line)]: \(msg)") }
    }

    static func equal<V: Equatable>(_ got: V, _ want: V, _ msg: String = "", line: UInt = #line) {
        if got == want { passed += 1 }
        else { failures += 1; print("  ✗ FAIL [\(line)]: \(msg) — got \(got), want \(want)") }
    }

    static func fixtureData(_ name: String) -> Data {
        let url = Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: "json")!
        return try! Data(contentsOf: url)
    }
}
