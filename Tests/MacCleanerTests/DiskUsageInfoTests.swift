import XCTest
@testable import MacCleaner

final class DiskUsageInfoTests: XCTestCase {
    func testCurrentReturnsValidVolume() {
        // The boot volume must always exist on a Mac running these tests.
        guard let info = DiskUsageInfo.current() else {
            XCTFail("DiskUsageInfo.current() returned nil on a real boot volume")
            return
        }
        XCTAssertGreaterThan(info.totalSpace, 0)
        XCTAssertGreaterThanOrEqual(info.freeSpace, 0)
        XCTAssertGreaterThanOrEqual(info.availableSpace, info.freeSpace - 1) // approximately equal or larger (purgeable)
        XCTAssertFalse(info.volumeName.isEmpty)
    }

    func testUsedComputation() {
        let info = DiskUsageInfo(
            volumeName: "Test",
            totalSpace: 1_000_000_000,
            freeSpace: 200_000_000,
            availableSpace: 250_000_000
        )
        // usedSpace is computed against availableSpace (Finder's "available")
        XCTAssertEqual(info.usedSpace, 750_000_000)
    }

    func testUsedPercentageZeroDivisionGuard() {
        let info = DiskUsageInfo(
            volumeName: "Empty",
            totalSpace: 0,
            freeSpace: 0,
            availableSpace: 0
        )
        XCTAssertEqual(info.usedPercentage, 0)
    }

    func testUsedPercentageInRange() {
        let info = DiskUsageInfo(
            volumeName: "Half",
            totalSpace: 100,
            freeSpace: 40,
            availableSpace: 50
        )
        XCTAssertEqual(info.usedPercentage, 0.5, accuracy: 0.0001)
    }
}
