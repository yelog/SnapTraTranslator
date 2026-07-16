import Dispatch
import Foundation
import os

nonisolated enum LookupPerformanceRoute: String, Sendable {
    case appStoreOCR
    case directOCR
    case accessibilitySelection
    case clipboardSelection
}

nonisolated enum LookupPerformanceStage: String, Sendable {
    case routeResolution
    case accessibilityProbe
    case clipboardFallback
    case captureMetadata
    case screenshot
    case ocr
    case overlayStatePublished
    case panelPresentation
    case translationFirstReady
    case dictionaryFirstReady
    case learningRecord
    case learningDefinition
    case ttsFetch
    case ttsStart
}

nonisolated enum LookupPerformanceOutcome: String, Sendable {
    case succeeded
    case cancelled
    case superseded
    case failed
    case cacheHit
    case cacheMiss
}

nonisolated enum LookupPerformanceAudioStartKind: String, Sendable {
    case appleDidStart
    case playAccepted
    case appleSubmissionProxy
}

nonisolated struct LookupPerformanceAudioStartMetadata: Equatable, Sendable {
    let kind: LookupPerformanceAudioStartKind
    let lookupID: UUID
}

nonisolated struct LookupPerformanceTrace: Hashable, Sendable {
    let lookupID: UUID
}

nonisolated protocol LookupPerformanceReporting: Sendable {
    func beginLookup(_ trace: LookupPerformanceTrace)
    func begin(_ stage: LookupPerformanceStage, trace: LookupPerformanceTrace)
    func end(
        _ stage: LookupPerformanceStage,
        trace: LookupPerformanceTrace,
        outcome: LookupPerformanceOutcome
    )
    func mark(_ stage: LookupPerformanceStage, trace: LookupPerformanceTrace)
    func markAudioStart(
        _ kind: LookupPerformanceAudioStartKind,
        trace: LookupPerformanceTrace
    )
    func endFirstPresentation(
        _ stage: LookupPerformanceStage,
        trace: LookupPerformanceTrace,
        outcome: LookupPerformanceOutcome
    )
    func recordRoute(_ route: LookupPerformanceRoute, trace: LookupPerformanceTrace)
    func finishLookup(_ trace: LookupPerformanceTrace, outcome: LookupPerformanceOutcome)
}

nonisolated protocol LookupPerformanceClock: Sendable {
    func nowNanoseconds() -> UInt64
}

nonisolated protocol LookupPerformanceEventSinking: Sendable {
    func record(_ event: LookupPerformanceEvent)
    func recordRoute(_ route: LookupPerformanceRoute, lookupID: UUID)
    func recordAudioStart(_ metadata: LookupPerformanceAudioStartMetadata)
}

extension LookupPerformanceEventSinking {
    func recordRoute(_ route: LookupPerformanceRoute, lookupID: UUID) {}
    func recordAudioStart(_ metadata: LookupPerformanceAudioStartMetadata) {}
}

nonisolated struct LookupPerformanceContext: Sendable {
    let reporter: any LookupPerformanceReporting
    let trace: LookupPerformanceTrace

    func begin(_ stage: LookupPerformanceStage) {
        reporter.begin(stage, trace: trace)
    }

    func end(_ stage: LookupPerformanceStage, outcome: LookupPerformanceOutcome) {
        reporter.end(stage, trace: trace, outcome: outcome)
    }

    func mark(_ stage: LookupPerformanceStage) {
        reporter.mark(stage, trace: trace)
    }

    func markAudioStart(_ kind: LookupPerformanceAudioStartKind) {
        reporter.markAudioStart(kind, trace: trace)
    }
}

nonisolated struct LookupPerformanceEvent: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case lookupBegan
        case stageBegan
        case stageEnded
        case milestone
        case firstPresentationEnded
        case lookupFinished
    }

    let kind: Kind
    let lookupID: UUID
    let stage: LookupPerformanceStage?
    let outcome: LookupPerformanceOutcome?
    let durationNanoseconds: UInt64?
}

nonisolated struct LookupPerformanceSystemClock: LookupPerformanceClock {
    func nowNanoseconds() -> UInt64 {
        DispatchTime.now().uptimeNanoseconds
    }
}

nonisolated final class LookupPerformanceReporter: LookupPerformanceReporting, @unchecked Sendable {
    private struct OpenStage {
        let stage: LookupPerformanceStage
        let startedAt: UInt64
    }

    private struct LookupState {
        let startedAt: UInt64
        var openStages: [String: OpenStage] = [:]
        var recordedMilestones: Set<String> = []
        var isFirstPresentationEnded = false
    }

    private let clock: any LookupPerformanceClock
    private let eventSink: any LookupPerformanceEventSinking
    private let lock = NSLock()
    private var lookups: [UUID: LookupState] = [:]

    init(
        clock: any LookupPerformanceClock = LookupPerformanceSystemClock(),
        eventSink: any LookupPerformanceEventSinking = LookupPerformanceSystemEventSink()
    ) {
        self.clock = clock
        self.eventSink = eventSink
    }

    func beginLookup(_ trace: LookupPerformanceTrace) {
        lock.lock()
        defer { lock.unlock() }

        guard lookups[trace.lookupID] == nil else { return }

        lookups[trace.lookupID] = LookupState(startedAt: clock.nowNanoseconds())
        eventSink.record(
            LookupPerformanceEvent(
                kind: .lookupBegan,
                lookupID: trace.lookupID,
                stage: nil,
                outcome: nil,
                durationNanoseconds: nil
            )
        )
    }

    func begin(_ stage: LookupPerformanceStage, trace: LookupPerformanceTrace) {
        lock.lock()
        defer { lock.unlock() }

        guard var state = lookups[trace.lookupID] else { return }
        guard state.openStages[stage.rawValue] == nil else { return }

        state.openStages[stage.rawValue] = OpenStage(
            stage: stage,
            startedAt: clock.nowNanoseconds()
        )
        lookups[trace.lookupID] = state
        eventSink.record(
            LookupPerformanceEvent(
                kind: .stageBegan,
                lookupID: trace.lookupID,
                stage: stage,
                outcome: nil,
                durationNanoseconds: nil
            )
        )
    }

    func end(
        _ stage: LookupPerformanceStage,
        trace: LookupPerformanceTrace,
        outcome: LookupPerformanceOutcome
    ) {
        lock.lock()
        defer { lock.unlock() }

        guard var state = lookups[trace.lookupID] else { return }
        guard let openStage = state.openStages.removeValue(forKey: stage.rawValue) else {
            return
        }

        let endedAt = clock.nowNanoseconds()
        lookups[trace.lookupID] = state
        eventSink.record(
            LookupPerformanceEvent(
                kind: .stageEnded,
                lookupID: trace.lookupID,
                stage: stage,
                outcome: outcome,
                durationNanoseconds: Self.duration(
                    from: openStage.startedAt,
                    to: endedAt
                )
            )
        )
    }

    func mark(_ stage: LookupPerformanceStage, trace: LookupPerformanceTrace) {
        lock.lock()
        defer { lock.unlock() }

        guard var state = lookups[trace.lookupID] else { return }
        guard state.recordedMilestones.insert(stage.rawValue).inserted else { return }

        let markedAt = clock.nowNanoseconds()
        eventSink.record(
            LookupPerformanceEvent(
                kind: .milestone,
                lookupID: trace.lookupID,
                stage: stage,
                outcome: nil,
                durationNanoseconds: Self.duration(from: state.startedAt, to: markedAt)
            )
        )

        if stage == .panelPresentation && !state.isFirstPresentationEnded {
            state.isFirstPresentationEnded = true
            eventSink.record(
                LookupPerformanceEvent(
                    kind: .firstPresentationEnded,
                    lookupID: trace.lookupID,
                    stage: .panelPresentation,
                    outcome: .succeeded,
                    durationNanoseconds: Self.duration(from: state.startedAt, to: markedAt)
                )
            )
        }

        lookups[trace.lookupID] = state
    }

    func markAudioStart(
        _ kind: LookupPerformanceAudioStartKind,
        trace: LookupPerformanceTrace
    ) {
        lock.lock()
        defer { lock.unlock() }

        guard var state = lookups[trace.lookupID] else { return }
        guard state.recordedMilestones.insert(LookupPerformanceStage.ttsStart.rawValue).inserted else {
            return
        }

        let markedAt = clock.nowNanoseconds()
        eventSink.record(
            LookupPerformanceEvent(
                kind: .milestone,
                lookupID: trace.lookupID,
                stage: .ttsStart,
                outcome: nil,
                durationNanoseconds: Self.duration(from: state.startedAt, to: markedAt)
            )
        )
        eventSink.recordAudioStart(
            LookupPerformanceAudioStartMetadata(
                kind: kind,
                lookupID: trace.lookupID
            )
        )
        lookups[trace.lookupID] = state
    }

    func endFirstPresentation(
        _ stage: LookupPerformanceStage,
        trace: LookupPerformanceTrace,
        outcome: LookupPerformanceOutcome
    ) {
        lock.lock()
        defer { lock.unlock() }

        guard var state = lookups[trace.lookupID], !state.isFirstPresentationEnded else {
            return
        }

        state.isFirstPresentationEnded = true
        let endedAt = clock.nowNanoseconds()
        lookups[trace.lookupID] = state
        eventSink.record(
            LookupPerformanceEvent(
                kind: .firstPresentationEnded,
                lookupID: trace.lookupID,
                stage: stage,
                outcome: outcome,
                durationNanoseconds: Self.duration(from: state.startedAt, to: endedAt)
            )
        )
    }

    func recordRoute(_ route: LookupPerformanceRoute, trace: LookupPerformanceTrace) {
        lock.lock()
        defer { lock.unlock() }

        guard lookups[trace.lookupID] != nil else { return }
        eventSink.recordRoute(route, lookupID: trace.lookupID)
    }

    func finishLookup(_ trace: LookupPerformanceTrace, outcome: LookupPerformanceOutcome) {
        lock.lock()
        defer { lock.unlock() }

        guard let state = lookups.removeValue(forKey: trace.lookupID) else { return }

        let finishedAt = clock.nowNanoseconds()
        for openStage in state.openStages.values.sorted(by: {
            $0.stage.rawValue < $1.stage.rawValue
        }) {
            eventSink.record(
                LookupPerformanceEvent(
                    kind: .stageEnded,
                    lookupID: trace.lookupID,
                    stage: openStage.stage,
                    outcome: outcome,
                    durationNanoseconds: Self.duration(
                        from: openStage.startedAt,
                        to: finishedAt
                    )
                )
            )
        }

        if !state.isFirstPresentationEnded {
            eventSink.record(
                LookupPerformanceEvent(
                    kind: .firstPresentationEnded,
                    lookupID: trace.lookupID,
                    stage: .panelPresentation,
                    outcome: outcome,
                    durationNanoseconds: Self.duration(
                        from: state.startedAt,
                        to: finishedAt
                    )
                )
            )
        }

        eventSink.record(
            LookupPerformanceEvent(
                kind: .lookupFinished,
                lookupID: trace.lookupID,
                stage: nil,
                outcome: outcome,
                durationNanoseconds: Self.duration(from: state.startedAt, to: finishedAt)
            )
        )
    }

    private static func duration(from start: UInt64, to end: UInt64) -> UInt64 {
        end >= start ? end - start : 0
    }
}

nonisolated final class LookupPerformanceSystemEventSink:
    LookupPerformanceEventSinking,
    @unchecked Sendable
{
    private struct Interval {
        let id: OSSignpostID
        var state: OSSignpostIntervalState?
    }

    private struct StageKey: Hashable {
        let lookupID: UUID
        let stage: String
    }

    private static let subsystem = "com.yelog.SnapTra-Translator"
    private static let category = "LookupPerformance"

    private let logger: Logger
    private let signposter: OSSignposter
    private let lock = NSLock()
    private var lookupIntervals: [UUID: Interval] = [:]
    private var stageIntervals: [StageKey: Interval] = [:]

    init() {
        let logger = Logger(subsystem: Self.subsystem, category: Self.category)
        self.logger = logger
        signposter = OSSignposter(logger: logger)
    }

    func record(_ event: LookupPerformanceEvent) {
        lock.lock()
        defer { lock.unlock() }

        let lookupID = event.lookupID.uuidString
        switch event.kind {
        case .lookupBegan:
            let id = signposter.makeSignpostID()
            let state = signposter.beginInterval(
                "LookupToFirstPresentation",
                id: id,
                "lookupID=\(lookupID, privacy: .public)"
            )
            lookupIntervals[event.lookupID] = Interval(id: id, state: state)
            logger.debug("lookup began lookupID=\(lookupID, privacy: .public)")

        case .stageBegan:
            guard let stage = event.stage else { return }
            let key = StageKey(lookupID: event.lookupID, stage: stage.rawValue)
            let id = signposter.makeSignpostID()
            let state = signposter.beginInterval(
                "LookupStage",
                id: id,
                "lookupID=\(lookupID, privacy: .public) stage=\(stage.rawValue, privacy: .public)"
            )
            stageIntervals[key] = Interval(id: id, state: state)

        case .stageEnded:
            guard
                let stage = event.stage,
                let outcome = event.outcome,
                let duration = event.durationNanoseconds
            else { return }
            let key = StageKey(lookupID: event.lookupID, stage: stage.rawValue)
            guard
                let interval = stageIntervals.removeValue(forKey: key),
                let state = interval.state
            else { return }
            signposter.endInterval(
                "LookupStage",
                state,
                "lookupID=\(lookupID, privacy: .public) stage=\(stage.rawValue, privacy: .public) outcome=\(outcome.rawValue, privacy: .public) duration_ns=\(duration, privacy: .public)"
            )

        case .milestone:
            guard let stage = event.stage, let duration = event.durationNanoseconds else {
                return
            }
            let id = lookupIntervals[event.lookupID]?.id ?? signposter.makeSignpostID()
            signposter.emitEvent(
                "LookupMilestone",
                id: id,
                "lookupID=\(lookupID, privacy: .public) stage=\(stage.rawValue, privacy: .public) duration_ns=\(duration, privacy: .public)"
            )

        case .firstPresentationEnded:
            guard
                let outcome = event.outcome,
                let duration = event.durationNanoseconds,
                var interval = lookupIntervals[event.lookupID],
                let state = interval.state
            else { return }
            signposter.endInterval(
                "LookupToFirstPresentation",
                state,
                "lookupID=\(lookupID, privacy: .public) outcome=\(outcome.rawValue, privacy: .public) duration_ns=\(duration, privacy: .public)"
            )
            interval.state = nil
            lookupIntervals[event.lookupID] = interval

        case .lookupFinished:
            guard let outcome = event.outcome, let duration = event.durationNanoseconds else {
                return
            }
            logger.debug(
                "lookup finished lookupID=\(lookupID, privacy: .public) outcome=\(outcome.rawValue, privacy: .public) duration_ns=\(duration, privacy: .public)"
            )
            lookupIntervals.removeValue(forKey: event.lookupID)
        }
    }

    func recordRoute(_ route: LookupPerformanceRoute, lookupID: UUID) {
        lock.lock()
        defer { lock.unlock() }

        let id = lookupIntervals[lookupID]?.id ?? signposter.makeSignpostID()
        let lookupIDString = lookupID.uuidString
        signposter.emitEvent(
            "LookupRoute",
            id: id,
            "lookupID=\(lookupIDString, privacy: .public) route=\(route.rawValue, privacy: .public)"
        )
        logger.debug(
            "lookup route lookupID=\(lookupIDString, privacy: .public) route=\(route.rawValue, privacy: .public)"
        )
    }

    func recordAudioStart(_ metadata: LookupPerformanceAudioStartMetadata) {
        lock.lock()
        defer { lock.unlock() }

        let id = lookupIntervals[metadata.lookupID]?.id ?? signposter.makeSignpostID()
        let lookupID = metadata.lookupID.uuidString
        signposter.emitEvent(
            "LookupAudioStart",
            id: id,
            "lookupID=\(lookupID, privacy: .public) kind=\(metadata.kind.rawValue, privacy: .public)"
        )
        logger.debug(
            "lookup audio start lookupID=\(lookupID, privacy: .public) kind=\(metadata.kind.rawValue, privacy: .public)"
        )
    }
}
