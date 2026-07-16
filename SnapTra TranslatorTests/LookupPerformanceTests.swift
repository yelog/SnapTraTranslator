import Foundation
import XCTest
@testable import SnapTra_Translator

final class LookupPerformanceTests: XCTestCase {
    func testFirstMilestoneForSameLookupIsRecordedOnlyOnce() {
        let clock = TestLookupPerformanceClock()
        let sink = RecordingLookupPerformanceEventSink()
        let reporter = LookupPerformanceReporter(clock: clock, eventSink: sink)
        let trace = LookupPerformanceTrace(lookupID: UUID())

        reporter.beginLookup(trace)
        clock.advance(by: 5_000_000)
        reporter.mark(.panelPresentation, trace: trace)
        reporter.mark(.panelPresentation, trace: trace)

        XCTAssertEqual(
            sink.events.filter {
                $0.kind == .milestone
                    && $0.lookupID == trace.lookupID
                    && $0.stage == .panelPresentation
            }.count,
            1
        )
        XCTAssertEqual(
            sink.events.filter {
                $0.kind == .firstPresentationEnded
                    && $0.lookupID == trace.lookupID
            }.count,
            1
        )
    }

    func testCancelledLookupClosesOpenPresentationIntervalOnce() {
        assertTerminalLookupClosesOpenPresentationIntervalOnce(outcome: .cancelled)
    }

    func testFailedLookupClosesOpenPresentationIntervalOnce() {
        assertTerminalLookupClosesOpenPresentationIntervalOnce(outcome: .failed)
    }

    func testDifferentLookupIDsKeepIndependentSignpostState() throws {
        let clock = TestLookupPerformanceClock()
        let sink = RecordingLookupPerformanceEventSink()
        let reporter = LookupPerformanceReporter(clock: clock, eventSink: sink)
        let firstTrace = LookupPerformanceTrace(lookupID: UUID())
        let secondTrace = LookupPerformanceTrace(lookupID: UUID())

        reporter.beginLookup(firstTrace)
        reporter.beginLookup(secondTrace)
        clock.advance(by: 4_000_000)
        reporter.mark(.panelPresentation, trace: firstTrace)
        clock.advance(by: 3_000_000)
        reporter.finishLookup(secondTrace, outcome: .cancelled)

        let presentationEvents = sink.events.filter { $0.kind == .firstPresentationEnded }
        let firstEvent = try XCTUnwrap(
            presentationEvents.first { $0.lookupID == firstTrace.lookupID }
        )
        let secondEvent = try XCTUnwrap(
            presentationEvents.first { $0.lookupID == secondTrace.lookupID }
        )

        XCTAssertEqual(firstEvent.outcome, .succeeded)
        XCTAssertEqual(firstEvent.durationNanoseconds, 4_000_000)
        XCTAssertEqual(secondEvent.outcome, .cancelled)
        XCTAssertEqual(secondEvent.durationNanoseconds, 7_000_000)
    }

    func testMonotonicClockProducesStageDurations() throws {
        let clock = TestLookupPerformanceClock(initialValue: 1_000_000)
        let sink = RecordingLookupPerformanceEventSink()
        let reporter = LookupPerformanceReporter(clock: clock, eventSink: sink)
        let trace = LookupPerformanceTrace(lookupID: UUID())

        reporter.beginLookup(trace)
        reporter.begin(.ocr, trace: trace)
        clock.advance(by: 12_500_000)
        reporter.end(.ocr, trace: trace, outcome: .succeeded)

        let event = try XCTUnwrap(
            sink.events.first {
                $0.kind == .stageEnded
                    && $0.lookupID == trace.lookupID
                    && $0.stage == .ocr
            }
        )
        XCTAssertEqual(event.durationNanoseconds, 12_500_000)
    }

    func testVisiblePanelCanEndFirstPresentationAtStatePublication() throws {
        let clock = TestLookupPerformanceClock()
        let sink = RecordingLookupPerformanceEventSink()
        let reporter = LookupPerformanceReporter(clock: clock, eventSink: sink)
        let trace = LookupPerformanceTrace(lookupID: UUID())

        reporter.beginLookup(trace)
        clock.advance(by: 3_000_000)
        reporter.mark(.overlayStatePublished, trace: trace)
        reporter.endFirstPresentation(
            .overlayStatePublished,
            trace: trace,
            outcome: .succeeded
        )
        reporter.endFirstPresentation(
            .overlayStatePublished,
            trace: trace,
            outcome: .succeeded
        )

        let event = try XCTUnwrap(
            sink.events.first { $0.kind == .firstPresentationEnded }
        )
        XCTAssertEqual(event.stage, .overlayStatePublished)
        XCTAssertEqual(event.durationNanoseconds, 3_000_000)
        XCTAssertEqual(
            sink.events.filter { $0.kind == .firstPresentationEnded }.count,
            1
        )
    }

    func testRouteMetadataUsesTypedRouteAndLookupID() {
        let sink = RecordingLookupPerformanceEventSink()
        let reporter = LookupPerformanceReporter(eventSink: sink)
        let trace = LookupPerformanceTrace(lookupID: UUID())

        reporter.beginLookup(trace)
        reporter.recordRoute(.directOCR, trace: trace)

        XCTAssertEqual(
            sink.routes,
            [RecordedLookupPerformanceRoute(route: .directOCR, lookupID: trace.lookupID)]
        )
    }

    func testReporterAPIHasNoSourceTextOrCoordinateFields() {
        let trace = LookupPerformanceTrace(lookupID: UUID())
        let traceFields = Set(Mirror(reflecting: trace).children.compactMap(\.label))
        let event = LookupPerformanceEvent(
            kind: .milestone,
            lookupID: trace.lookupID,
            stage: .translationFirstReady,
            outcome: nil,
            durationNanoseconds: nil
        )
        let eventFields = Set(Mirror(reflecting: event).children.compactMap(\.label))

        XCTAssertEqual(traceFields, ["lookupID"])
        XCTAssertEqual(
            eventFields,
            ["kind", "lookupID", "stage", "outcome", "durationNanoseconds"]
        )
    }

    private func assertTerminalLookupClosesOpenPresentationIntervalOnce(
        outcome: LookupPerformanceOutcome,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let clock = TestLookupPerformanceClock()
        let sink = RecordingLookupPerformanceEventSink()
        let reporter = LookupPerformanceReporter(clock: clock, eventSink: sink)
        let trace = LookupPerformanceTrace(lookupID: UUID())

        reporter.beginLookup(trace)
        clock.advance(by: 8_000_000)
        reporter.finishLookup(trace, outcome: outcome)
        reporter.finishLookup(trace, outcome: outcome)

        let presentationEvents = sink.events.filter {
            $0.kind == .firstPresentationEnded && $0.lookupID == trace.lookupID
        }
        let finishEvents = sink.events.filter {
            $0.kind == .lookupFinished && $0.lookupID == trace.lookupID
        }

        XCTAssertEqual(presentationEvents.count, 1, file: file, line: line)
        XCTAssertEqual(presentationEvents.first?.outcome, outcome, file: file, line: line)
        XCTAssertEqual(
            presentationEvents.first?.durationNanoseconds,
            8_000_000,
            file: file,
            line: line
        )
        XCTAssertEqual(finishEvents.count, 1, file: file, line: line)
    }
}

private final class TestLookupPerformanceClock: LookupPerformanceClock, @unchecked Sendable {
    private let lock = NSLock()
    private var value: UInt64

    init(initialValue: UInt64 = 0) {
        value = initialValue
    }

    func nowNanoseconds() -> UInt64 {
        lock.withLock { value }
    }

    func advance(by durationNanoseconds: UInt64) {
        lock.withLock {
            value += durationNanoseconds
        }
    }
}

private final class RecordingLookupPerformanceEventSink:
    LookupPerformanceEventSinking,
    @unchecked Sendable
{
    private let lock = NSLock()
    private var recordedEvents: [LookupPerformanceEvent] = []
    private var recordedRoutes: [RecordedLookupPerformanceRoute] = []

    var events: [LookupPerformanceEvent] {
        lock.withLock { recordedEvents }
    }

    var routes: [RecordedLookupPerformanceRoute] {
        lock.withLock { recordedRoutes }
    }

    func record(_ event: LookupPerformanceEvent) {
        lock.withLock {
            recordedEvents.append(event)
        }
    }

    func recordRoute(_ route: LookupPerformanceRoute, lookupID: UUID) {
        lock.withLock {
            recordedRoutes.append(
                RecordedLookupPerformanceRoute(route: route, lookupID: lookupID)
            )
        }
    }
}

private struct RecordedLookupPerformanceRoute: Equatable {
    let route: LookupPerformanceRoute
    let lookupID: UUID
}
