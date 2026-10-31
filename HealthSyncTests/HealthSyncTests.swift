// Tests for the logic that can be wrong without HealthKit: the schedule, the sleep
// clustering, the day key, the activity table, and the folder bookmark.

import HealthKit
import XCTest
@testable import HealthSync

final class ScheduleTests: XCTestCase {
    private let cal = Calendar(identifier: .gregorian)

    private func date(_ h: Int, _ m: Int) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 3, day: 14, hour: h, minute: m))!
    }

    func testNextFireTakesTheLaterSlotToday() {
        let next = Schedule.nextFire(after: date(10, 0), times: [7 * 60, 12 * 60, 23 * 60 + 30], calendar: cal)
        XCTAssertEqual(cal.component(.hour, from: next), 12)
        XCTAssertEqual(cal.component(.minute, from: next), 0)
        XCTAssertEqual(cal.startOfDay(for: next), cal.startOfDay(for: date(10, 0)))
    }

    func testNextFireWrapsToTomorrowAfterTheLastSlot() {
        let next = Schedule.nextFire(after: date(23, 45), times: [7 * 60, 22 * 60 + 30], calendar: cal)
        XCTAssertEqual(cal.component(.hour, from: next), 7)
        XCTAssertEqual(cal.component(.minute, from: next), 0)
        XCTAssertEqual(next, cal.date(byAdding: .day, value: 1, to: date(7, 0)))
    }

    func testNextFireWithAnEmptyListUsesTheDefault() {
        let next = Schedule.nextFire(after: date(10, 0), times: [], calendar: cal)
        XCTAssertEqual(cal.component(.hour, from: next), 23)
        XCTAssertEqual(cal.component(.minute, from: next), 30)
    }

    func testNextFireIsAlwaysStrictlyInTheFuture() {
        for slot in [0, 7 * 60, 23 * 60 + 59] {
            let now = date(slot / 60, slot % 60)
            XCTAssertGreaterThan(Schedule.nextFire(after: now, times: [slot], calendar: cal), now)
        }
    }
}

final class SleepSessionTests: XCTestCase {
    private let cal = Calendar.current

    private func sample(_ value: HKCategoryValueSleepAnalysis, hoursAgo: Double, hours: Double) -> HKCategorySample {
        let start = Date().addingTimeInterval(-hoursAgo * 3600)
        return HKCategorySample(type: HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!,
                                value: value.rawValue, start: start,
                                end: start.addingTimeInterval(hours * 3600))
    }

    func testAGapAboveOneHourSplitsTheNightInTwo() {
        let rows = Exporter.sessions(from: [
            sample(.asleepCore, hoursAgo: 9, hours: 4),
            sample(.asleepDeep, hoursAgo: 5, hours: 1.5),
            sample(.asleepCore, hoursAgo: 0.5, hours: 2),     // 3 h after the block above
        ])
        XCTAssertEqual(rows.count, 2)
    }

    func testContiguousStagesStayOneSession() {
        let rows = Exporter.sessions(from: [
            sample(.asleepCore, hoursAgo: 8, hours: 3),
            sample(.asleepDeep, hoursAgo: 5, hours: 1),
            sample(.asleepREM, hoursAgo: 4, hours: 1.5),
        ])
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0]["hours"] as? Double ?? 0, 5.5, accuracy: 0.02)
        let stages = rows[0]["stages"] as? [String: Double] ?? [:]
        XCTAssertEqual(stages["deep"] ?? 0, 1, accuracy: 0.02)
        XCTAssertEqual(stages["rem"] ?? 0, 1.5, accuracy: 0.02)
    }

    func testAwakeTimeIsNotCountedAsSleep() {
        let rows = Exporter.sessions(from: [
            sample(.asleepCore, hoursAgo: 8, hours: 4),
            sample(.awake, hoursAgo: 4, hours: 0.5),
            sample(.asleepCore, hoursAgo: 3.5, hours: 2),
        ])
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0]["hours"] as? Double ?? 0, 6, accuracy: 0.02)   // 4 + 2, not 6.5
        let stages = rows[0]["stages"] as? [String: Double] ?? [:]
        XCTAssertEqual(stages["awake"] ?? 0, 0.5, accuracy: 0.02)
    }

    func testEverySessionCarriesTheKeysTheServerReads() {
        let rows = Exporter.sessions(from: [sample(.asleepCore, hoursAgo: 7, hours: 3)])
        XCTAssertEqual(rows.count, 1)
        for key in ["start", "end", "day", "hours", "stages"] {
            XCTAssertNotNil(rows[0][key], "missing \(key)")
        }
    }
}

final class ExportShapeTests: XCTestCase {
    func testDayKeyIsTheFormatTheServerParses() {
        let cal = Calendar(identifier: .gregorian)
        let stamp = cal.date(from: DateComponents(year: 2026, month: 1, day: 5, hour: 23, minute: 59))!
        XCTAssertEqual(Exporter.dayKey(stamp), "2026-01-05")
    }

    func testActivityNamesCoverTheTypesThisOwnerUses() {
        XCTAssertEqual(Exporter.activityNames[11], "Cross Training")
        XCTAssertEqual(Exporter.activityNames[63], "HIIT")
        XCTAssertEqual(Exporter.activityNames[37], "Running")
        XCTAssertGreaterThan(Exporter.activityNames.count, 80)
    }
}

final class FolderBookmarkTests: XCTestCase {
    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: BOOKMARK_KEY)
        super.tearDown()
    }

    func testAFolderSurvivesASaveAndResolve() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("hs-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        try FolderStore.save(dir)
        let resolved = try XCTUnwrap(FolderStore.url())
        XCTAssertEqual(resolved.lastPathComponent, dir.lastPathComponent)
    }

    func testAGarbageBookmarkIsDiscardedInsteadOfCrashing() {
        UserDefaults.standard.set(Data("not a bookmark".utf8), forKey: BOOKMARK_KEY)
        XCTAssertNil(FolderStore.url())
        XCTAssertNil(UserDefaults.standard.data(forKey: BOOKMARK_KEY), "a stale bookmark must be removed")
    }
}

final class ExportSummaryTests: XCTestCase {
    func testTheSummaryReportsWhatTheCardShows() {
        let summary = ExportSummary(metrics: 18, workouts: 3, sessions: 2)
        XCTAssertEqual(summary.metrics, 18)
        XCTAssertEqual(summary.workouts, 3)
        XCTAssertEqual(summary.sessions, 2)
    }
}
