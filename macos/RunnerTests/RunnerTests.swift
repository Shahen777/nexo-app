import Cocoa
import XCTest
@testable import Nexo

final class RunnerTests: XCTestCase {
    func testFeedAcceptsHTTPSWithCustomPort() {
        let value = "https://updates.example.test:8444/mac/appcast.xml"
        XCTAssertEqual(UpdaterConfiguration.feedURL(from: value)?.absoluteString, value)
    }

    func testFeedRejectsInvalidTransportCredentialsAndFragments() {
        for value in [
            "", "http://updates.example.test/appcast.xml", "file:///tmp/appcast.xml",
            "https:///appcast.xml", "https://user:password@updates.example.test/appcast.xml",
            "https://updates.example.test/appcast.xml#fragment", "https://updates.example.test:0/appcast.xml",
            "https://updates.example.test:65536/appcast.xml"
        ] {
            XCTAssertNil(UpdaterConfiguration.feedURL(from: value), value)
        }
        XCTAssertNil(UpdaterConfiguration.feedURL(from: nil))
        XCTAssertNil(UpdaterConfiguration.feedURL(from: 42))
    }

    @MainActor
    func testTerminationRequestWaitsForCentralFlutterExit() {
        let delegate = AppDelegate()
        var requests = 0
        delegate.requestTermination = { requests += 1 }

        XCTAssertEqual(delegate.applicationShouldTerminate(NSApplication.shared), .terminateCancel)
        XCTAssertEqual(requests, 1)
    }
}
