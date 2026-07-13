import Darwin
import Foundation

@main
enum TestMain {
    static func main() async {
        let tests = OutputAndScannerTests.all
            + SystemCommandRunnerTests.all
            + ConversionEngineTests.all
            + FolderJobTests.all
            + AppCoordinatorTests.all
            + BootstrapTests.all
        var failures = 0

        for test in tests {
            do {
                try await test.body()
                print("✓ \(test.name)")
            } catch {
                failures += 1
                print("✗ \(test.name): \(error)")
            }
        }

        print("\n\(tests.count - failures)/\(tests.count) tests passed")
        if failures > 0 { exit(1) }
    }
}
