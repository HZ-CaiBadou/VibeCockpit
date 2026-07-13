import XCTest
@testable import VibeCockpitCore

final class CodexUsageResponseTests: XCTestCase {

    private func decode(_ json: String) throws -> CodexUsageResponse {
        try JSONDecoder().decode(CodexUsageResponse.self, from: Data(json.utf8))
    }

    func testMissingPrimaryWindowDoesNotCreateFiveHourPlaceholder() throws {
        let response = try decode("""
        {
          "rate_limit": {
            "secondary_window": {
              "used_percent": "25.5",
              "limit_window_seconds": "604800",
              "reset_after_seconds": "3600"
            }
          }
        }
        """)

        let usage = response.toCodexUsageData()

        XCTAssertNil(usage.primary)
        XCTAssertEqual(usage.secondary?.percentage, 25.5)
        XCTAssertEqual(usage.secondary?.windowSeconds, 604800)
        XCTAssertEqual(usage.secondary?.compactWindowLabel, "7d")
        XCTAssertNotNil(usage.secondary?.resetsAt)
    }

    func testPresentZeroUsageSecondaryWindowIsRetained() throws {
        let response = try decode("""
        {
          "rate_limit": {
            "secondary_window": {
              "used_percent": 0,
              "limit_window_seconds": 604800,
              "reset_at": null,
              "reset_after_seconds": null
            }
          }
        }
        """)

        let usage = response.toCodexUsageData()

        XCTAssertEqual(usage.secondary?.percentage, 0)
        XCTAssertNil(usage.secondary?.resetsAt)
    }

    func testMalformedCreditsDoNotDiscardValidQuotaWindows() throws {
        let response = try decode("""
        {
          "rate_limit": {
            "primary_window": {
              "used_percent": 120,
              "limit_window_seconds": 3600,
              "reset_at": 1900000000
            }
          },
          "credits": "unexpected-schema"
        }
        """)

        let usage = response.toCodexUsageData()

        XCTAssertEqual(usage.primary?.percentage, 100)
        XCTAssertEqual(usage.primary?.windowSeconds, 3600)
        XCTAssertNil(usage.extraUsage)
    }

    func testNullUsagePercentageFallsBackToZeroInsteadOfFailingDecode() throws {
        let response = try decode("""
        {
          "rate_limit": {
            "primary_window": {
              "used_percent": null,
              "limit_window_seconds": 3600,
              "reset_after_seconds": 0
            }
          }
        }
        """)

        let usage = response.toCodexUsageData()

        XCTAssertEqual(usage.primary?.percentage, 0)
        XCTAssertNotNil(usage.primary?.resetsAt)
    }
}
