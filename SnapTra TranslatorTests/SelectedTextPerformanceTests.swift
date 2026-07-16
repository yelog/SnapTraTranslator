import XCTest
@testable import SnapTra_Translator

final class SinglePressLookupRequestTests: XCTestCase {
    func testRequestKeepsTriggerPointWhenLaterPointChanges() {
        let triggerPoint = CGPoint(x: 120, y: 240)
        let request = makeRequest(mouseLocation: triggerPoint)
        let laterPoint = CGPoint(x: 800, y: 600)

        XCTAssertNotEqual(laterPoint, triggerPoint)
        XCTAssertEqual(request.mouseLocation, triggerPoint)
    }

    func testEachContinuousLookupCanFreezeItsOwnPoint() {
        let first = makeRequest(mouseLocation: CGPoint(x: 100, y: 200))
        let second = makeRequest(mouseLocation: CGPoint(x: 140, y: 260))

        XCTAssertNotEqual(first.lookupID, second.lookupID)
        XCTAssertEqual(first.mouseLocation, CGPoint(x: 100, y: 200))
        XCTAssertEqual(second.mouseLocation, CGPoint(x: 140, y: 260))
    }

    func testRequestKeepsSelectedTextProbeContextFrozen() {
        let probeRequest = SelectedTextProbeRequest(
            mouseLocation: CGPoint(x: 120, y: 240),
            frontmostApplicationProcessIdentifier: 42,
            sourceAppIdentifier: "com.example.source",
            globalScreenMaxY: 1_080
        )
        let request = SinglePressLookupRequest(
            lookupID: UUID(),
            mouseLocation: probeRequest.mouseLocation,
            supportsSelectedText: true,
            selectedTextEnabled: true,
            clipboardFallbackEnabled: true,
            hasAccessibilityPermission: true,
            selectedTextProbeRequest: probeRequest
        )

        XCTAssertEqual(request.selectedTextProbeRequest, probeRequest)
    }

    func testUnsupportedChannelUsesOCROnlyPolicy() {
        let request = makeRequest(supportsSelectedText: false)

        XCTAssertEqual(request.executionPolicy, .ocrOnly)
    }

    func testDisabledSelectedTextUsesOCROnlyPolicy() {
        let request = makeRequest(selectedTextEnabled: false)

        XCTAssertEqual(request.executionPolicy, .ocrOnly)
    }

    func testMissingAccessibilityUsesOCROnlyPolicy() {
        let request = makeRequest(hasAccessibilityPermission: false)

        XCTAssertEqual(request.executionPolicy, .ocrOnly)
    }

    func testSelectionFirstPolicyPreservesClipboardSetting() {
        XCTAssertEqual(
            makeRequest(clipboardFallbackEnabled: true).executionPolicy,
            .selectionFirst(allowsClipboardFallback: true)
        )
        XCTAssertEqual(
            makeRequest(clipboardFallbackEnabled: false).executionPolicy,
            .selectionFirst(allowsClipboardFallback: false)
        )
    }

    private func makeRequest(
        mouseLocation: CGPoint = CGPoint(x: 120, y: 240),
        supportsSelectedText: Bool = true,
        selectedTextEnabled: Bool = true,
        clipboardFallbackEnabled: Bool = true,
        hasAccessibilityPermission: Bool = true
    ) -> SinglePressLookupRequest {
        SinglePressLookupRequest(
            lookupID: UUID(),
            mouseLocation: mouseLocation,
            supportsSelectedText: supportsSelectedText,
            selectedTextEnabled: selectedTextEnabled,
            clipboardFallbackEnabled: clipboardFallbackEnabled,
            hasAccessibilityPermission: hasAccessibilityPermission
        )
    }
}

final class SelectedTextProbePolicyTests: XCTestCase {
    func testKnownRangeFastPathDoesNotReadMarkerAttributedOrBounds() throws {
        let calls = ProbeCallRecorder()
        let candidate = makeCandidate(
            calls: calls,
            directText: "Hello",
            range: NSRange(location: 3, length: 5),
            rangeText: "unused",
            markerText: "unused",
            attributedText: "unused",
            bounds: CGRect(x: 10, y: 20, width: 50, height: 18)
        )

        let snapshot = try XCTUnwrap(resolve(candidate))

        XCTAssertEqual(snapshot.text, "Hello")
        XCTAssertEqual(snapshot.selectedRange, NSRange(location: 3, length: 5))
        XCTAssertNil(snapshot.bounds)
        XCTAssertEqual(calls.values, ["selectedText", "selectedRange"])
    }

    func testRangeStringSuccessDoesNotEnterMarkerPhase() throws {
        let calls = ProbeCallRecorder()
        let candidate = makeCandidate(
            calls: calls,
            directText: nil,
            range: NSRange(location: 8, length: 5),
            rangeText: "Hello",
            markerText: "unused",
            attributedText: "unused",
            bounds: CGRect(x: 10, y: 20, width: 50, height: 18)
        )

        let snapshot = try XCTUnwrap(resolve(candidate))

        XCTAssertEqual(snapshot.text, "Hello")
        XCTAssertNil(snapshot.bounds)
        XCTAssertEqual(
            calls.values,
            ["selectedText", "selectedRange", "rangeString"]
        )
    }

    func testMarkerStringSuccessDoesNotReadAttributedString() throws {
        let calls = ProbeCallRecorder()
        let candidate = makeCandidate(
            calls: calls,
            directText: nil,
            range: nil,
            rangeText: nil,
            markerText: "Hello",
            attributedText: "unused",
            bounds: CGRect(x: 10, y: 20, width: 50, height: 18)
        )

        let snapshot = try XCTUnwrap(resolve(candidate))

        XCTAssertEqual(snapshot.text, "Hello")
        XCTAssertFalse(calls.values.contains("markerAttributedString"))
        XCTAssertEqual(
            calls.values,
            [
                "selectedText",
                "selectedRange",
                "markerRange",
                "markerString",
                "markerBounds",
            ]
        )
    }

    func testUnknownRangeReadsBoundsForGeometryConfidence() throws {
        let calls = ProbeCallRecorder()
        let candidate = makeCandidate(
            calls: calls,
            directText: "Hello",
            range: nil,
            rangeText: nil,
            markerText: "unused",
            attributedText: "unused",
            bounds: CGRect(x: 10, y: 20, width: 50, height: 18)
        )

        let snapshot = try XCTUnwrap(resolve(candidate))

        XCTAssertEqual(snapshot.selectedRange.location, NSNotFound)
        XCTAssertEqual(snapshot.bounds, CGRect(x: 10, y: 20, width: 50, height: 18))
        XCTAssertTrue(calls.values.contains("markerBounds"))
        XCTAssertFalse(calls.values.contains("markerString"))
        XCTAssertFalse(calls.values.contains("markerAttributedString"))
    }

    func testFirstHoveredCandidateSuccessDoesNotEnumerateFocusedCandidates() throws {
        let calls = ProbeCallRecorder()
        let first = makeCandidate(
            calls: calls,
            directText: "Hello",
            range: NSRange(location: 0, length: 5),
            rangeText: nil,
            markerText: nil,
            attributedText: nil,
            bounds: nil
        )
        var requestedCandidates = 0
        let candidates = AnySequence {
            AnyIterator<SelectedTextProbeCandidate> {
                requestedCandidates += 1
                switch requestedCandidates {
                case 1:
                    return first
                case 2:
                    XCTFail("fast path should not request the focused candidate")
                    return self.makeCandidate(
                        calls: calls,
                        directText: "Focused",
                        range: NSRange(location: 0, length: 7),
                        rangeText: nil,
                        markerText: nil,
                        attributedText: nil,
                        bounds: nil
                    )
                default:
                    return nil
                }
            }
        }

        let snapshot = try XCTUnwrap(
            SelectedTextProbePolicy.snapshot(
                candidates: candidates,
                sourceAppIdentifier: "com.apple.TextEdit",
                normalizeBounds: { $0 },
                diagnostics: SelectedTextDiagnostics(isEnabled: false)
            )
        )

        XCTAssertEqual(snapshot.text, "Hello")
        XCTAssertEqual(requestedCandidates, 1)
    }

    func testSoftBudgetDoesNotChangeSelectionResult() throws {
        let expected = SelectedTextSnapshot(
            text: "Hello",
            selectedRange: NSRange(location: 0, length: 5),
            bounds: nil,
            sourceAppIdentifier: "com.apple.TextEdit"
        )
        var observation: SelectedTextProbeObservation?

        let result = SelectedTextProbeSoftBudget.observe(
            expected,
            durationNanoseconds: SelectedTextProbeObservation.softBudgetNanoseconds + 1,
            observer: { observation = $0 }
        )

        XCTAssertEqual(result, expected)
        XCTAssertTrue(try XCTUnwrap(observation).exceededSoftBudget)
    }

    func testDisabledDiagnosticsDoesNotEvaluateMessageAutoclosure() {
        let diagnostics = SelectedTextDiagnostics(isEnabled: false)
        var evaluationCount = 0

        diagnostics.log({
            evaluationCount += 1
            return "expensive AX debug summary"
        }())

        XCTAssertEqual(evaluationCount, 0)
    }

    private func resolve(
        _ candidate: SelectedTextProbeCandidate
    ) -> SelectedTextSnapshot? {
        SelectedTextProbePolicy.snapshot(
            candidates: AnySequence([candidate]),
            sourceAppIdentifier: "com.apple.TextEdit",
            normalizeBounds: { $0 },
            diagnostics: SelectedTextDiagnostics(isEnabled: false)
        )
    }

    private func makeCandidate(
        calls: ProbeCallRecorder,
        directText: String?,
        range: NSRange?,
        rangeText: String?,
        markerText: String?,
        attributedText: String?,
        bounds: CGRect?
    ) -> SelectedTextProbeCandidate {
        SelectedTextProbeCandidate(
            context: "candidate[0] hovered#0",
            debugSummary: {
                calls.record("debugSummary")
                return "debug"
            },
            selectedText: {
                calls.record("selectedText")
                return directText
            },
            selectedRange: {
                calls.record("selectedRange")
                guard let range else { return nil }
                return SelectedTextProbeRange(
                    range: range,
                    string: {
                        calls.record("rangeString")
                        return rangeText
                    },
                    bounds: {
                        calls.record("rangeBounds")
                        return bounds
                    }
                )
            },
            selectedTextMarkerRange: {
                calls.record("markerRange")
                guard markerText != nil || attributedText != nil || bounds != nil else {
                    return nil
                }
                return SelectedTextProbeMarkerRange(
                    string: {
                        calls.record("markerString")
                        return markerText
                    },
                    attributedString: {
                        calls.record("markerAttributedString")
                        return attributedText.map(NSAttributedString.init(string:))
                    },
                    bounds: {
                        calls.record("markerBounds")
                        return bounds
                    }
                )
            }
        )
    }
}

final class SelectedTextProbeExecutorTests: XCTestCase {
    func testConcurrentProbesRunWithMaximumConcurrencyOfOne() async throws {
        let executor = SelectedTextProbeExecutor(label: #function)
        let concurrency = ProbeConcurrencyRecorder()

        async let first: Int = executor.execute { _ in
            concurrency.enter()
            Thread.sleep(forTimeInterval: 0.04)
            concurrency.leave()
            return 1
        }
        async let second: Int = executor.execute { _ in
            concurrency.enter()
            Thread.sleep(forTimeInterval: 0.04)
            concurrency.leave()
            return 2
        }

        let values = try await [first, second]
        XCTAssertEqual(Set(values), [1, 2])
        XCTAssertEqual(concurrency.maximum, 1)
    }

    func testProbeWorkDoesNotRunOnMainThread() async throws {
        let executor = SelectedTextProbeExecutor(label: #function)

        let ranOnMainThread = try await executor.execute { _ in
            Thread.isMainThread
        }

        XCTAssertFalse(ranOnMainThread)
    }

    func testCancellationStopsBeforeTheNextProbePhase() async {
        let executor = SelectedTextProbeExecutor(label: #function)
        let didStart = expectation(description: "probe phase started")
        let mayContinue = DispatchSemaphore(value: 0)
        let calls = ProbeCallRecorder()

        let task = Task {
            try await executor.execute { cancellation -> SelectedTextSnapshot? in
                let candidate = SelectedTextProbeCandidate(
                    context: "candidate",
                    debugSummary: { "debug" },
                    selectedText: {
                        calls.record("selectedText")
                        didStart.fulfill()
                        mayContinue.wait()
                        return "Hello"
                    },
                    selectedRange: {
                        calls.record("selectedRange")
                        return SelectedTextProbeRange(
                            range: NSRange(location: 0, length: 5),
                            string: { nil },
                            bounds: { nil }
                        )
                    },
                    selectedTextMarkerRange: {
                        calls.record("markerRange")
                        return nil
                    }
                )
                return SelectedTextProbePolicy.snapshot(
                    candidates: AnySequence([candidate]),
                    sourceAppIdentifier: nil,
                    normalizeBounds: { $0 },
                    diagnostics: SelectedTextDiagnostics(isEnabled: false),
                    isCancelled: { cancellation.isCancelled }
                )
            }
        }

        await fulfillment(of: [didStart], timeout: 1)
        task.cancel()
        mayContinue.signal()

        do {
            _ = try await task.value
            XCTFail("cancelled probe should throw CancellationError")
        } catch is CancellationError {
            // Expected.
        } catch {
            XCTFail("unexpected error: \(error)")
        }

        XCTAssertEqual(calls.values, ["selectedText"])
    }
}

@MainActor
final class SinglePressLookupCoordinatorTests: XCTestCase {
    func testKnownAXSelectionDoesNotStartOCRCandidate() async {
        let request = makeRequest()
        let dependencies = CoordinatorDependencyRecorder()
        let routeState = CoordinatorRouteState()
        let snapshot = accessibilitySnapshot(text: "Known selection")

        let decision: SinglePressLookupDecision<String> = await SinglePressLookupCoordinator.resolve(
            request: request,
            accessibilityProbe: { receivedRequest in
                await dependencies.record(.accessibility, request: receivedRequest)
                return SinglePressLookupResolution(
                    intent: .selectedTextSentence(snapshot),
                    shouldTryClipboardFallback: false
                )
            },
            clipboardProbe: { receivedRequest in
                await dependencies.record(.clipboard, request: receivedRequest)
                return nil
            },
            loadOCRCandidate: { receivedRequest in
                await dependencies.record(.ocr, request: receivedRequest)
                routeState.recordCandidateLoaded()
                return "unexpected OCR"
            },
            routeResolved: { routeState.recordRoute($0) }
        )

        guard case .selectedText(let resolvedSnapshot) = decision else {
            return XCTFail("known AX selection should win")
        }
        XCTAssertEqual(resolvedSnapshot, snapshot)
        let accessibilityCount = await dependencies.count(.accessibility)
        let clipboardCount = await dependencies.count(.clipboard)
        let ocrCount = await dependencies.count(.ocr)
        XCTAssertEqual(accessibilityCount, 1)
        XCTAssertEqual(clipboardCount, 0)
        XCTAssertEqual(ocrCount, 0)
        XCTAssertEqual(routeState.routes, [.selectedText(.accessibility)])
        XCTAssertEqual(routeState.events, [.route(.selectedText(.accessibility))])
    }

    func testFreshClipboardWinsEvenWhenOCRFinishesFirst() async {
        let request = makeRequest()
        let dependencies = CoordinatorDependencyRecorder()
        let routeState = CoordinatorRouteState()
        let clipboardValue = ControlledCoordinatorValue<SelectedTextSnapshot?>()
        let ocrValue = ControlledCoordinatorValue<String>()
        let clipboardStarted = expectation(description: "clipboard started")
        let ocrStarted = expectation(description: "OCR started")
        let ocrFinished = expectation(description: "OCR finished first")
        let freshClipboard = clipboardSnapshot(text: "Fresh clipboard")

        let decisionTask = Task { @MainActor in
            await SinglePressLookupCoordinator.resolve(
                request: request,
                accessibilityProbe: { receivedRequest in
                    await dependencies.record(.accessibility, request: receivedRequest)
                    return self.uncertainAccessibilityResolution()
                },
                clipboardProbe: { receivedRequest in
                    await dependencies.record(.clipboard, request: receivedRequest)
                    clipboardStarted.fulfill()
                    let value = await clipboardValue.wait()
                    routeState.markClipboardFreshnessResolved()
                    return value
                },
                loadOCRCandidate: { receivedRequest in
                    await dependencies.record(.ocr, request: receivedRequest)
                    ocrStarted.fulfill()
                    let value = await ocrValue.wait()
                    routeState.recordCandidateLoaded()
                    ocrFinished.fulfill()
                    return value
                },
                routeResolved: { routeState.recordRoute($0) }
            )
        }

        await fulfillment(of: [clipboardStarted, ocrStarted], timeout: 1)
        ocrValue.resume(returning: "prefetched OCR")
        await fulfillment(of: [ocrFinished], timeout: 1)

        XCTAssertTrue(routeState.routes.isEmpty)
        XCTAssertFalse(routeState.isClipboardFreshnessResolved)

        clipboardValue.resume(returning: freshClipboard)
        let decision = await decisionTask.value

        guard case .selectedText(let resolvedSnapshot) = decision else {
            return XCTFail("fresh clipboard must remain authoritative")
        }
        XCTAssertEqual(resolvedSnapshot, freshClipboard)
        XCTAssertEqual(routeState.routes, [.selectedText(.clipboard)])
        XCTAssertEqual(routeState.routeFreshnessStates, [true])
        let ocrCount = await dependencies.count(.ocr)
        XCTAssertEqual(ocrCount, 1)
        XCTAssertEqual(routeState.routes.count, 1)
    }

    func testUnchangedClipboardNilConsumesPrefetchedOCRCandidate() async {
        let request = makeRequest()
        let dependencies = CoordinatorDependencyRecorder()
        let routeState = CoordinatorRouteState()
        let clipboardValue = ControlledCoordinatorValue<SelectedTextSnapshot?>()
        let ocrValue = ControlledCoordinatorValue<String>()
        let clipboardStarted = expectation(description: "clipboard started")
        let ocrStarted = expectation(description: "OCR started")
        let ocrFinished = expectation(description: "OCR prefetched")

        let decisionTask = Task { @MainActor in
            await SinglePressLookupCoordinator.resolve(
                request: request,
                accessibilityProbe: { receivedRequest in
                    await dependencies.record(.accessibility, request: receivedRequest)
                    return self.uncertainAccessibilityResolution()
                },
                clipboardProbe: { receivedRequest in
                    await dependencies.record(.clipboard, request: receivedRequest)
                    clipboardStarted.fulfill()
                    let value = await clipboardValue.wait()
                    routeState.markClipboardFreshnessResolved()
                    return value
                },
                loadOCRCandidate: { receivedRequest in
                    await dependencies.record(.ocr, request: receivedRequest)
                    ocrStarted.fulfill()
                    let value = await ocrValue.wait()
                    routeState.recordCandidateLoaded()
                    ocrFinished.fulfill()
                    return value
                },
                routeResolved: { routeState.recordRoute($0) }
            )
        }

        await fulfillment(of: [clipboardStarted, ocrStarted], timeout: 1)
        ocrValue.resume(returning: "prefetched OCR")
        await fulfillment(of: [ocrFinished], timeout: 1)
        XCTAssertTrue(routeState.routes.isEmpty)

        clipboardValue.resume(returning: nil)
        let decision = await decisionTask.value

        guard case .ocr(let candidate) = decision else {
            return XCTFail("unchanged clipboard should use prefetched OCR")
        }
        XCTAssertEqual(candidate, "prefetched OCR")
        let ocrCount = await dependencies.count(.ocr)
        XCTAssertEqual(ocrCount, 1)
        XCTAssertEqual(routeState.routes, [.ocr])
        XCTAssertEqual(routeState.routeFreshnessStates, [true])
        XCTAssertEqual(
            routeState.events,
            [.candidateLoaded, .clipboardFreshnessResolved, .route(.ocr)]
        )
    }

    func testAppStoreOCRPathDoesNotInvokeAXOrClipboard() async {
        let request = makeRequest(
            supportsSelectedText: false,
            selectedTextEnabled: false,
            clipboardFallbackEnabled: false,
            hasAccessibilityPermission: false
        )
        let dependencies = CoordinatorDependencyRecorder()
        let routeState = CoordinatorRouteState()

        let decision: SinglePressLookupDecision<String> = await SinglePressLookupCoordinator.resolve(
            request: request,
            accessibilityProbe: { receivedRequest in
                await dependencies.record(.accessibility, request: receivedRequest)
                return self.uncertainAccessibilityResolution()
            },
            clipboardProbe: { receivedRequest in
                await dependencies.record(.clipboard, request: receivedRequest)
                return nil
            },
            loadOCRCandidate: { receivedRequest in
                await dependencies.record(.ocr, request: receivedRequest)
                routeState.recordCandidateLoaded()
                return "App Store OCR"
            },
            routeResolved: { routeState.recordRoute($0) }
        )

        guard case .ocr(let candidate) = decision else {
            return XCTFail("App Store path should resolve directly to OCR")
        }
        XCTAssertEqual(candidate, "App Store OCR")
        let accessibilityCount = await dependencies.count(.accessibility)
        let clipboardCount = await dependencies.count(.clipboard)
        let ocrCount = await dependencies.count(.ocr)
        XCTAssertEqual(accessibilityCount, 0)
        XCTAssertEqual(clipboardCount, 0)
        XCTAssertEqual(ocrCount, 1)
        XCTAssertEqual(routeState.routes, [.ocr])
        XCTAssertEqual(routeState.events, [.route(.ocr), .candidateLoaded])
        XCTAssertEqual(routeState.routes.count, 1)
    }

    func testCancelledLookupCannotReturnCompletedOCRCandidate() async {
        let request = makeRequest()
        let dependencies = CoordinatorDependencyRecorder()
        let routeState = CoordinatorRouteState()
        let clipboardValue = ControlledCoordinatorValue<SelectedTextSnapshot?>()
        let ocrValue = ControlledCoordinatorValue<String>()
        let clipboardStarted = expectation(description: "clipboard started")
        let ocrStarted = expectation(description: "OCR started")
        let ocrFinished = expectation(description: "late OCR completed")

        let decisionTask = Task { @MainActor in
            await SinglePressLookupCoordinator.resolve(
                request: request,
                accessibilityProbe: { receivedRequest in
                    await dependencies.record(.accessibility, request: receivedRequest)
                    return self.uncertainAccessibilityResolution()
                },
                clipboardProbe: { receivedRequest in
                    await dependencies.record(.clipboard, request: receivedRequest)
                    clipboardStarted.fulfill()
                    return await clipboardValue.wait()
                },
                loadOCRCandidate: { receivedRequest in
                    await dependencies.record(.ocr, request: receivedRequest)
                    ocrStarted.fulfill()
                    let value = await ocrValue.wait()
                    routeState.recordCandidateLoaded()
                    ocrFinished.fulfill()
                    return value
                },
                routeResolved: { routeState.recordRoute($0) }
            )
        }

        await fulfillment(of: [clipboardStarted, ocrStarted], timeout: 1)
        ocrValue.resume(returning: "must not commit")
        await fulfillment(of: [ocrFinished], timeout: 1)

        decisionTask.cancel()
        clipboardValue.resume(returning: nil)
        let decision = await decisionTask.value

        guard case .cancelled = decision else {
            return XCTFail("superseded lookup must discard its completed OCR candidate")
        }
        let ocrCount = await dependencies.count(.ocr)
        XCTAssertEqual(ocrCount, 1)
        XCTAssertTrue(routeState.routes.isEmpty)
        XCTAssertEqual(routeState.events, [.candidateLoaded])
    }

    func testCancellationAfterStaleClipboardResultCancelsPendingOCRCandidate() async {
        let request = makeRequest()
        let dependencies = CoordinatorDependencyRecorder()
        let routeState = CoordinatorRouteState()
        let clipboardValue = ControlledCoordinatorValue<SelectedTextSnapshot?>()
        let clipboardStarted = expectation(description: "clipboard started")
        let ocrStarted = expectation(description: "OCR started")
        let ocrCancellationObserved = expectation(description: "OCR cancellation observed")
        let ocrRouteResolved = expectation(description: "OCR route resolved")

        let decisionTask = Task { @MainActor in
            await SinglePressLookupCoordinator.resolve(
                request: request,
                accessibilityProbe: { receivedRequest in
                    await dependencies.record(.accessibility, request: receivedRequest)
                    return self.uncertainAccessibilityResolution()
                },
                clipboardProbe: { receivedRequest in
                    await dependencies.record(.clipboard, request: receivedRequest)
                    clipboardStarted.fulfill()
                    return await clipboardValue.wait()
                },
                loadOCRCandidate: { receivedRequest in
                    await dependencies.record(.ocr, request: receivedRequest)
                    ocrStarted.fulfill()
                    while !Task.isCancelled {
                        await Task.yield()
                    }
                    ocrCancellationObserved.fulfill()
                    return "cancelled OCR"
                },
                routeResolved: { route in
                    routeState.recordRoute(route)
                    if route == .ocr {
                        ocrRouteResolved.fulfill()
                    }
                }
            )
        }

        await fulfillment(of: [clipboardStarted, ocrStarted], timeout: 1)
        clipboardValue.resume(returning: nil)
        await fulfillment(of: [ocrRouteResolved], timeout: 1)

        decisionTask.cancel()
        await fulfillment(of: [ocrCancellationObserved], timeout: 1)

        guard case .cancelled = await decisionTask.value else {
            return XCTFail("superseded lookup must cancel pending speculative OCR")
        }
        let ocrCount = await dependencies.count(.ocr)
        XCTAssertEqual(ocrCount, 1)
        XCTAssertEqual(routeState.routes, [.ocr])
        XCTAssertFalse(routeState.events.contains(.candidateLoaded))
    }

    func testAllDependenciesReceiveTheSameFrozenMousePoint() async {
        let frozenPoint = CGPoint(x: 321, y: 654)
        let request = makeRequest(mouseLocation: frozenPoint)
        let dependencies = CoordinatorDependencyRecorder()
        let routeState = CoordinatorRouteState()

        let decision: SinglePressLookupDecision<String> = await SinglePressLookupCoordinator.resolve(
            request: request,
            accessibilityProbe: { receivedRequest in
                await dependencies.record(.accessibility, request: receivedRequest)
                return self.uncertainAccessibilityResolution()
            },
            clipboardProbe: { receivedRequest in
                await dependencies.record(.clipboard, request: receivedRequest)
                routeState.markClipboardFreshnessResolved()
                return nil
            },
            loadOCRCandidate: { receivedRequest in
                await dependencies.record(.ocr, request: receivedRequest)
                routeState.recordCandidateLoaded()
                return "OCR"
            },
            routeResolved: { routeState.recordRoute($0) }
        )

        guard case .ocr = decision else {
            return XCTFail("nil clipboard should resolve to OCR")
        }

        for dependency in CoordinatorDependency.allCases {
            let receivedRequests = await dependencies.requests(for: dependency)
            XCTAssertEqual(receivedRequests.count, 1, "\(dependency)")
            XCTAssertEqual(receivedRequests.first?.mouseLocation, frozenPoint, "\(dependency)")
            XCTAssertEqual(receivedRequests.first?.lookupID, request.lookupID, "\(dependency)")
        }
        XCTAssertEqual(routeState.routes, [.ocr])
        XCTAssertEqual(routeState.routeFreshnessStates, [true])
        XCTAssertEqual(routeState.routes.count, 1)
    }

    private func makeRequest(
        mouseLocation: CGPoint = CGPoint(x: 120, y: 240),
        supportsSelectedText: Bool = true,
        selectedTextEnabled: Bool = true,
        clipboardFallbackEnabled: Bool = true,
        hasAccessibilityPermission: Bool = true
    ) -> SinglePressLookupRequest {
        SinglePressLookupRequest(
            lookupID: UUID(),
            mouseLocation: mouseLocation,
            supportsSelectedText: supportsSelectedText,
            selectedTextEnabled: selectedTextEnabled,
            clipboardFallbackEnabled: clipboardFallbackEnabled,
            hasAccessibilityPermission: hasAccessibilityPermission
        )
    }

    private func uncertainAccessibilityResolution() -> SinglePressLookupResolution {
        SinglePressLookupResolution(
            intent: .ocrWord,
            shouldTryClipboardFallback: true
        )
    }

    private func accessibilitySnapshot(text: String) -> SelectedTextSnapshot {
        SelectedTextSnapshot(
            text: text,
            selectedRange: NSRange(location: 0, length: text.utf16.count),
            bounds: nil,
            sourceAppIdentifier: "com.apple.TextEdit"
        )
    }

    private func clipboardSnapshot(text: String) -> SelectedTextSnapshot {
        SelectedTextSnapshot(
            text: text,
            selectedRange: NSRange(location: NSNotFound, length: text.utf16.count),
            bounds: nil,
            sourceAppIdentifier: "com.example.Source",
            source: .clipboard
        )
    }
}

private final class ProbeCallRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recordedValues: [String] = []

    var values: [String] {
        lock.withLock { recordedValues }
    }

    func record(_ value: String) {
        lock.withLock {
            recordedValues.append(value)
        }
    }
}

private final class ProbeConcurrencyRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var currentValue = 0
    private var maximumValue = 0

    var maximum: Int {
        lock.withLock { maximumValue }
    }

    func enter() {
        lock.withLock {
            currentValue += 1
            maximumValue = max(maximumValue, currentValue)
        }
    }

    func leave() {
        lock.withLock {
            currentValue -= 1
        }
    }
}

private enum CoordinatorDependency: CaseIterable, Hashable, Sendable {
    case accessibility
    case clipboard
    case ocr
}

private actor CoordinatorDependencyRecorder {
    private var recordedRequests: [CoordinatorDependency: [SinglePressLookupRequest]] = [:]

    func record(
        _ dependency: CoordinatorDependency,
        request: SinglePressLookupRequest
    ) {
        recordedRequests[dependency, default: []].append(request)
    }

    func count(_ dependency: CoordinatorDependency) -> Int {
        recordedRequests[dependency, default: []].count
    }

    func requests(
        for dependency: CoordinatorDependency
    ) -> [SinglePressLookupRequest] {
        recordedRequests[dependency, default: []]
    }
}

@MainActor
private final class CoordinatorRouteState {
    enum Event: Equatable {
        case candidateLoaded
        case clipboardFreshnessResolved
        case route(SinglePressLookupResolvedRoute)
    }

    private(set) var routes: [SinglePressLookupResolvedRoute] = []
    private(set) var events: [Event] = []
    private(set) var routeFreshnessStates: [Bool] = []
    private(set) var isClipboardFreshnessResolved = false

    func recordCandidateLoaded() {
        events.append(.candidateLoaded)
    }

    func markClipboardFreshnessResolved() {
        isClipboardFreshnessResolved = true
        events.append(.clipboardFreshnessResolved)
    }

    func recordRoute(_ route: SinglePressLookupResolvedRoute) {
        routes.append(route)
        routeFreshnessStates.append(isClipboardFreshnessResolved)
        events.append(.route(route))
    }
}

@MainActor
private final class ControlledCoordinatorValue<Value> {
    private enum State {
        case idle
        case waiting(CheckedContinuation<Value, Never>)
        case resolved(Value)
    }

    private var state: State = .idle

    func wait() async -> Value {
        switch state {
        case .resolved(let value):
            return value
        case .idle:
            return await withCheckedContinuation { continuation in
                state = .waiting(continuation)
            }
        case .waiting:
            preconditionFailure("ControlledCoordinatorValue only supports one waiter")
        }
    }

    func resume(returning value: Value) {
        switch state {
        case .idle:
            state = .resolved(value)
        case .waiting(let continuation):
            state = .resolved(value)
            continuation.resume(returning: value)
        case .resolved:
            preconditionFailure("ControlledCoordinatorValue can only resolve once")
        }
    }
}
