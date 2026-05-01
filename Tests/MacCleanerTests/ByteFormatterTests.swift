import XCTest
@testable import MacCleaner

final class ByteFormatterTests: XCTestCase {
    func testZero() {
        XCTAssertEqual(ByteFormatter.format(Int64(0)), "0 B")
    }

    func testNegativeReturnsZero() {
        XCTAssertEqual(ByteFormatter.format(Int64(-100)), "0 B")
    }

    func testBytesUnderKilobyte() {
        XCTAssertEqual(ByteFormatter.format(Int64(1)), "1 B")
        XCTAssertEqual(ByteFormatter.format(Int64(512)), "512 B")
        XCTAssertEqual(ByteFormatter.format(Int64(1023)), "1023 B")
    }

    func testKilobyteBoundary() {
        XCTAssertEqual(ByteFormatter.format(Int64(1024)), "1.0 KB")
        XCTAssertEqual(ByteFormatter.format(Int64(2048)), "2.0 KB")
    }

    func testMegabyte() {
        XCTAssertEqual(ByteFormatter.format(Int64(1_048_576)), "1.0 MB")
        XCTAssertEqual(ByteFormatter.format(Int64(1_572_864)), "1.5 MB")
    }

    func testGigabyte() {
        XCTAssertEqual(ByteFormatter.format(Int64(1_073_741_824)), "1.0 GB")
    }

    func testTerabyte() {
        XCTAssertEqual(ByteFormatter.format(Int64(1_099_511_627_776)), "1.0 TB")
    }

    func testUInt64Overload() {
        XCTAssertEqual(ByteFormatter.format(UInt64(1024)), "1.0 KB")
        XCTAssertEqual(ByteFormatter.format(UInt64.max), ByteFormatter.format(Int64.max))
    }
}
