import Foundation

/// Stands in for XCTest, which is unavailable without Xcode. Prints one line per
/// case and exits non-zero on any failure, so the normal red/green cycle holds.
@MainActor
final class Harness {
    private var failures: [String] = []
    private var total = 0

    func equal<T: Equatable>(_ name: String, _ actual: T, _ expected: T) {
        total += 1
        if actual == expected {
            print("  ok    \(name)")
        } else {
            print("  FAIL  \(name) — expected \(expected), got \(actual)")
            failures.append(name)
        }
    }

    func check(_ name: String, _ condition: @autoclosure () -> Bool) {
        equal(name, condition(), true)
    }

    func section(_ title: String) {
        print("\n\(title)")
    }

    func finish() -> Never {
        print("")
        if failures.isEmpty {
            print("PASSED \(total)/\(total)")
            exit(0)
        }
        print("FAILED \(failures.count)/\(total)")
        for name in failures { print("  - \(name)") }
        exit(1)
    }
}
