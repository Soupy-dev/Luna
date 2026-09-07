import XCTest
@testable import Eclipse

#if os(iOS)

final class StreamReachabilityVerdictTests: XCTestCase {

    private let probeURL = URL(string: "https://example.com/stream.mp4")
        ?? URL(fileURLWithPath: "/stream.mp4")

    private func verdict(
        status: Int,
        contentType: String? = nil,
        contentLength: String? = nil,
        body: Data = Data()
    ) -> StreamReachabilityVerdict {
        var headers: [String: String] = [:]
        if let contentType {
            headers["Content-Type"] = contentType
        }
        if let contentLength {
            headers["Content-Length"] = contentLength
        }
        return StreamReachabilityProbe.evaluate(
            status: status,
            responseHeaders: headers,
            body: body,
            requestedURL: probeURL
        )
    }

    private func isDead(_ verdict: StreamReachabilityVerdict) -> Bool {
        if case .confidentlyDead = verdict { return true }
        return false
    }

    private func isIndeterminate(_ verdict: StreamReachabilityVerdict) -> Bool {
        if case .indeterminate = verdict { return true }
        return false
    }

    func testNotFoundIsConfidentlyDead() {
        XCTAssertEqual(verdict(status: 404), .confidentlyDead(.notFound))
    }

    func testStructurallyUnplayableURLsAreConfidentlyDead() {
        for failure: SkyStreamSecurityError in [
            .emptyURL, .malformedURL, .unsupportedScheme, .invalidHost
        ] {
            XCTAssertEqual(
                StreamReachabilityProbe.verdictForSecurityPolicyFailure(failure),
                .confidentlyDead(.unsafeAddress)
            )
        }
    }

    func testUnprobeableButPossiblyPlayableAddressesFailOpen() {
        XCTAssertEqual(
            StreamReachabilityProbe.verdictForSecurityPolicyFailure(.prohibitedAddress("192.168.1.20")),
            .indeterminate(.unverifiableByEclipse("private-address"))
        )
        XCTAssertEqual(
            StreamReachabilityProbe.verdictForSecurityPolicyFailure(.prohibitedHost),
            .indeterminate(.unverifiableByEclipse("private-address"))
        )
        for failure: SkyStreamSecurityError in [
            .insecureTransport, .credentialsInURL, .httpsDowngrade, .tooManyRedirects
        ] {
            let verdict = StreamReachabilityProbe.verdictForSecurityPolicyFailure(failure)
            XCTAssertEqual(verdict?.allowsPlaybackAttempt, true)
        }
    }

    func testInPlayerStartupProbeTreatsUnreachablePolicyFailuresAsIndeterminate() {
        for failure: SkyStreamSecurityError in [
            .prohibitedAddress("192.168.1.20"), .prohibitedHost,
            .insecureTransport, .credentialsInURL, .httpsDowngrade, .tooManyRedirects
        ] {
            guard case .slowOrIndeterminate(let reason)? =
                SourceHealthMonitor.probeResult(forUnverifiableSecurityFailure: failure) else {
                XCTFail("expected slowOrIndeterminate for \(failure)")
                continue
            }
            XCTAssertTrue(reason.contains("unverifiable"))
        }

        XCTAssertNil(SourceHealthMonitor.probeResult(forUnverifiableSecurityFailure: .malformedURL))
        XCTAssertNil(SourceHealthMonitor.probeResult(forUnverifiableSecurityFailure: .unsupportedScheme))
    }

    func testCapabilityBearingURLsBypassDisposableActiveProbe() {
        let capabilityURLs = [
            "https://cdn.example/video.mp4?X-Amz-Signature=abc",
            "https://cdn.example/video.mp4?token=short-lived",
            "https://cdn.example/video.mp4?opaque=0123456789abcdefghijklmn",
            "https://cdn.example/AbCDef0123456789-opaque-token/master.m3u8"
        ]
        for rawURL in capabilityURLs {
            guard let url = URL(string: rawURL) else {
                XCTFail("invalid test URL")
                continue
            }
            XCTAssertTrue(StreamReachabilityProbe.shouldBypassActiveProbe(for: url))
        }

        XCTAssertFalse(
            StreamReachabilityProbe.shouldBypassActiveProbe(
                for: URL(string: "https://cdn.example/video.mp4?quality=1080&lang=en")
                    ?? probeURL
            )
        )
        XCTAssertFalse(StreamReachabilityProbe.shouldBypassActiveProbe(for: probeURL))
    }

    func testGoneIsConfidentlyDead() {
        XCTAssertEqual(verdict(status: 410), .confidentlyDead(.gone))
    }

    func testForbiddenIsIndeterminate() {
        XCTAssertEqual(verdict(status: 403), .indeterminate(.forbidden))
        XCTAssertEqual(verdict(status: 401), .indeterminate(.forbidden))
        XCTAssertEqual(verdict(status: 451), .indeterminate(.forbidden))
    }

    func testMethodNotAllowedIsIndeterminate() {
        XCTAssertEqual(verdict(status: 405), .indeterminate(.methodUnsupported))
    }

    func testRangeNotSatisfiableIsReachable() {
        XCTAssertEqual(verdict(status: 416), .reachable)
    }

    func testRateLimitedIsIndeterminate() {
        XCTAssertEqual(verdict(status: 429), .indeterminate(.rateLimited))
    }

    func testServerErrorsAreIndeterminate() {
        for status in [500, 502, 503, 504] {
            XCTAssertEqual(verdict(status: status), .indeterminate(.serverError(status)))
        }
    }

    func testRedirectReachingEvaluationIsIndeterminate() {
        XCTAssertTrue(isIndeterminate(verdict(status: 302)))
        XCTAssertTrue(isIndeterminate(verdict(status: 301)))
    }

    func testNoContentIsConfidentlyDead() {
        XCTAssertEqual(verdict(status: 204), .confidentlyDead(.emptyBody))
    }

    func testPartialContentWithMediaTypeIsReachable() {
        XCTAssertEqual(
            verdict(status: 206, contentType: "video/mp4", body: Data([0x00, 0x01, 0x02])),
            .reachable
        )
    }

    func testHTMLPayloadOnSuccessIsConfidentlyDead() {
        let body = Data("<!doctype html><html><body>gone</body></html>".utf8)
        XCTAssertTrue(isDead(verdict(status: 200, contentType: "text/html", body: body)))
    }

    func testJSONErrorPayloadIsConfidentlyDead() {
        let body = Data("{\"error\":\"no such file\"}".utf8)
        XCTAssertTrue(isDead(verdict(status: 200, contentType: "application/json", body: body)))
    }

    func testErrorDocumentIsDetectedWithoutAContentType() {
        let body = Data("<html><head><title>404</title></head></html>".utf8)
        XCTAssertTrue(isDead(verdict(status: 200, body: body)))
    }

    func testDashManifestIsReachable() {
        let body = Data("<?xml version=\"1.0\"?><MPD></MPD>".utf8)
        XCTAssertEqual(
            verdict(status: 200, contentType: "application/dash+xml", body: body),
            .reachable
        )
    }

    func testDashManifestContentTypeWithEmptyBodyIsReachable() {
        XCTAssertEqual(
            verdict(status: 200, contentType: "application/dash+xml"),
            .reachable
        )
    }

    func testDashManifestBodyWithGenericXMLContentTypeIsReachable() {
        let body = Data(
            "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<MPD xmlns=\"urn:mpeg:dash:schema:mpd:2011\" type=\"static\"><Period></Period></MPD>".utf8
        )
        XCTAssertEqual(verdict(status: 200, contentType: "application/xml", body: body), .reachable)
        XCTAssertEqual(verdict(status: 200, contentType: "text/xml", body: body), .reachable)
    }

    func testDashManifestBodyWithoutContentTypeIsReachable() {
        let body = Data("<?xml version=\"1.0\"?><MPD></MPD>".utf8)
        XCTAssertEqual(verdict(status: 200, body: body), .reachable)
    }

    func testDashManifestBodyWithLeadingCommentIsReachable() {
        let body = Data("<?xml version=\"1.0\"?><!-- generated --><MPD minBufferTime=\"PT1.5S\"></MPD>".utf8)
        XCTAssertEqual(verdict(status: 200, contentType: "application/xml", body: body), .reachable)
    }

    func testNamespacedDashManifestBodyIsReachable() {
        let body = Data("<?xml version=\"1.0\"?><mpd:MPD xmlns:mpd=\"urn:mpeg:dash:schema:mpd:2011\"></mpd:MPD>".utf8)
        XCTAssertEqual(verdict(status: 200, contentType: "application/xml", body: body), .reachable)
    }

    func testGenericXMLPayloadRemainsConfidentlyDead() {
        let body = Data("<?xml version=\"1.0\"?><error><message>not found</message></error>".utf8)
        XCTAssertTrue(isDead(verdict(status: 200, contentType: "application/xml", body: body)))
        XCTAssertTrue(isDead(verdict(status: 200, contentType: "text/xml", body: body)))
    }

    func testHLSBodyIsReachableRegardlessOfContentType() {
        let body = Data("#EXTM3U\n#EXT-X-VERSION:3\n".utf8)
        XCTAssertEqual(verdict(status: 200, contentType: "text/plain", body: body), .reachable)
    }

    func testMpegURLContentTypeIsReachable() {
        XCTAssertEqual(
            verdict(status: 200, contentType: "application/vnd.apple.mpegurl"),
            .reachable
        )
    }

    func testContentTypeParametersAreIgnored() {
        let body = Data("<!doctype html><html></html>".utf8)
        XCTAssertTrue(
            isDead(verdict(status: 200, contentType: "text/html; charset=utf-8", body: body))
        )
    }

    func testImagePayloadIsConfidentlyDead() {
        let body = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10])
        XCTAssertTrue(isDead(verdict(status: 200, contentType: "image/jpeg", body: body)))
    }

    func testImageContentTypeWithoutImageBytesIsReachable() {
        let body = Data([0x00, 0x01, 0x02, 0x03, 0x04])
        XCTAssertEqual(
            verdict(status: 200, contentType: "image/jpeg", body: body),
            .reachable
        )
    }

    func testDeclaredEmptyBodyIsConfidentlyDead() {
        XCTAssertEqual(
            verdict(status: 200, contentLength: "0"),
            .confidentlyDead(.emptyBody)
        )
    }

    func testEmptyBodyWithoutDeclaredLengthFailsOpen() {
        XCTAssertEqual(verdict(status: 200), .reachable)
    }

    func testUnrecognisedBinaryPayloadFailsOpen() {
        let body = Data([0x1A, 0x45, 0xDF, 0xA3, 0x9F, 0x42])
        XCTAssertEqual(verdict(status: 200, body: body), .reachable)
    }

    func testCloudflareChallengeOverridesNotFound() {
        let body = Data("<html>__cf_chl_opt window._cf_chl_opt</html>".utf8)
        let result = verdict(status: 404, contentType: "text/html", body: body)
        XCTAssertFalse(isDead(result))
        XCTAssertTrue(isIndeterminate(result))
    }

    func testCloudflareChallengeHeaderOverridesPayloadSniffing() {
        let result = StreamReachabilityProbe.evaluate(
            status: 403,
            responseHeaders: ["cf-mitigated": "challenge"],
            body: Data("<!doctype html><html></html>".utf8),
            requestedURL: probeURL
        )
        XCTAssertTrue(isIndeterminate(result))
    }

    func testNoStatusOutsideTheDeadSetEverSkipsASource() {
        for status in 100...599 {
            let result = verdict(status: status)
            let skips = !result.allowsPlaybackAttempt
            let expectsSkip = status == 404 || status == 410 || status == 204
            XCTAssertEqual(
                skips,
                expectsSkip,
                "status \(status) produced \(result.summary)"
            )
        }
    }
}

final class SourceHealthRecordCompatibilityTests: XCTestCase {

    func testRecordsWrittenBeforeProbeTrackingStillDecode() throws {
        let legacy = """
        {
            "sourceId": "example",
            "sourceName": "Example",
            "endpointStatus": "healthy",
            "lastEndpointCheckedAt": 760000000
        }
        """

        let data = Data(legacy.utf8)
        let record = try JSONDecoder().decode(SourceHealthRecord.self, from: data)

        XCTAssertEqual(record.sourceId, "example")
        XCTAssertNil(record.consecutiveProbeFailureCount)
        XCTAssertNil(record.lastProbeFailureAt)
    }

    func testPersistedRecordsRejectCorruptFailureCountersAndDates() throws {
        let corruptCounter = Data(
            #"{"source":{"sourceId":"source","sourceName":"Source","endpointStatus":"healthy","consecutiveProbeFailureCount":9223372036854775807}}"#.utf8
        )
        XCTAssertNil(SourceHealthStore.decodedRecords(from: corruptCounter))

        let corruptDate = Data(
            #"{"source":{"sourceId":"source","sourceName":"Source","endpointStatus":"healthy","lastEndpointCheckedAt":1e300}}"#.utf8
        )
        XCTAssertNil(SourceHealthStore.decodedRecords(from: corruptDate))
    }

    func testPersistedRecordsAcceptBoundedLegacyPayload() throws {
        let payload = Data(
            #"{"source":{"sourceId":"source","sourceName":"Source","endpointStatus":"healthy","consecutiveProbeFailureCount":2}}"#.utf8
        )
        let decoded = try XCTUnwrap(SourceHealthStore.decodedRecords(from: payload))
        XCTAssertEqual(decoded["source"]?.consecutiveProbeFailureCount, 2)
    }
}

final class StremioNumericBoundaryTests: XCTestCase {

    func testHostileStreamAndSubtitleArraysAreBoundedWithStableFirstWinsDeduplication() throws {
        var rawSubtitles: [[String: Any]] = [
            ["url": "https://subtitles.example/0.vtt", "lang": "first"],
            ["url": "https://subtitles.example/0.vtt", "lang": "duplicate"]
        ]
        rawSubtitles.append(contentsOf: (2..<(StremioDecodingLimits.subtitlesPerStream + 50)).map {
            ["url": "https://subtitles.example/\($0).vtt", "lang": "lang-\($0)"]
        })
        let streamData = try JSONSerialization.data(withJSONObject: [
            "url": "https://media.example/video.m3u8",
            "subtitles": rawSubtitles
        ])
        let stream = try JSONDecoder().decode(StremioStream.self, from: streamData)
        let decodedSubtitles = try XCTUnwrap(stream.subtitles)
        XCTAssertEqual(decodedSubtitles.count, StremioDecodingLimits.subtitlesPerStream - 1)
        XCTAssertEqual(decodedSubtitles.first?.lang, "first")
        XCTAssertEqual(
            decodedSubtitles.last?.url,
            "https://subtitles.example/\(StremioDecodingLimits.subtitlesPerStream - 1).vtt"
        )

        var rawStreams: [[String: Any]] = [
            ["url": "https://media.example/0.m3u8", "title": "first"],
            ["url": "https://media.example/0.m3u8", "title": "duplicate"]
        ]
        rawStreams.append(contentsOf: (2..<(StremioDecodingLimits.streamsPerResponse + 50)).map {
            ["url": "https://media.example/\($0).m3u8", "title": "stream-\($0)"]
        })
        let responseData = try JSONSerialization.data(withJSONObject: ["streams": rawStreams])
        let response = try JSONDecoder().decode(StremioStreamResponse.self, from: responseData)
        let decodedStreams = try XCTUnwrap(response.streams)
        XCTAssertEqual(decodedStreams.count, StremioDecodingLimits.streamsPerResponse - 1)
        XCTAssertEqual(decodedStreams.first?.title, "first")
        XCTAssertEqual(
            decodedStreams.last?.url,
            "https://media.example/\(StremioDecodingLimits.streamsPerResponse - 1).m3u8"
        )

        let standaloneSubtitleData = try JSONSerialization.data(withJSONObject: [
            "subtitles": (0..<(StremioDecodingLimits.subtitlesPerResponse + 50)).map {
                ["url": "https://standalone-subtitles.example/\($0).vtt"]
            }
        ])
        let standalone = try JSONDecoder().decode(
            StremioSubtitleResponse.self,
            from: standaloneSubtitleData
        )
        XCTAssertEqual(
            standalone.subtitles?.count,
            StremioDecodingLimits.subtitlesPerResponse
        )
    }

    func testStremioRetryAfterRejectsNonfiniteValuesAndRepairsPoisonedDates() {
        for rawValue in ["nan", "inf", "-inf", nil] as [String?] {
            XCTAssertEqual(
                StremioRetryAfterPolicy.delaySeconds(from: rawValue),
                StremioRetryAfterPolicy.fallbackSeconds
            )
        }
        XCTAssertEqual(StremioRetryAfterPolicy.delaySeconds(from: "-50"), 1)
        XCTAssertEqual(StremioRetryAfterPolicy.delaySeconds(from: "1e300"), 120)
        XCTAssertEqual(StremioRetryAfterPolicy.delaySeconds(from: "17.5"), 17.5)

        let now = Date(timeIntervalSinceReferenceDate: 1_000)
        for poisoned in [
            Date(timeIntervalSinceReferenceDate: .nan),
            Date(timeIntervalSinceReferenceDate: .infinity),
            Date(timeIntervalSinceReferenceDate: -.infinity)
        ] {
            XCTAssertEqual(
                StremioRetryAfterPolicy.normalizedSchedulerDate(poisoned, now: now),
                now
            )
        }
        XCTAssertEqual(
            StremioRetryAfterPolicy.normalizedSchedulerDate(
                now.addingTimeInterval(10_000),
                now: now
            ),
            now.addingTimeInterval(StremioRetryAfterPolicy.maximumSeconds)
        )
    }

    func testUnrepresentableTMDBNumberIsIgnoredWithoutTrapping() throws {
        let payload = Data(
            #"{"id":"item","name":"Example","tmdb_id":1e300}"#.utf8
        )

        let preview = try JSONDecoder().decode(StremioMetaPreview.self, from: payload)

        XCTAssertNil(preview.tmdbId)
    }

    func testUnrepresentableStreamVideoSizeIsIgnoredWithoutTrapping() throws {
        let payload = Data(
            #"{"url":"https://example.com/video","behaviorHints":{"videoSize":1e300}}"#.utf8
        )

        let stream = try JSONDecoder().decode(StremioStream.self, from: payload)

        XCTAssertNil(stream.behaviorHints?.videoSize)
    }

    func testFractionalStreamVideoSizePreservesLegacyTruncation() throws {
        let payload = Data(
            #"{"url":"https://example.com/video","behaviorHints":{"videoSize":123.9}}"#.utf8
        )

        let stream = try JSONDecoder().decode(StremioStream.self, from: payload)

        XCTAssertEqual(stream.behaviorHints?.videoSize, 123)
    }
}

final class ServiceJavaScriptResultBoundaryTests: XCTestCase {
    func testEpisodeResultsAreCappedAndRejectInvalidNumbersAndHrefs() throws {
        var rows = (0..<4_100).map { index in
            ["number": index + 1, "href": "/episode/\(index + 1)"] as [String: Any]
        }
        rows[0] = ["number": 1e300, "href": "/overflow"]
        rows[1] = ["number": 2, "href": "https://example.test/ok\r\nInjected: yes"]
        let data = try JSONSerialization.data(withJSONObject: rows)

        let parsed = try JSController.boundedEpisodeLinks(from: data)

        XCTAssertEqual(parsed.rawCount, 4_100)
        XCTAssertEqual(parsed.episodes.count, 4_096)
        XCTAssertEqual(parsed.episodes.first?.number, 3)
        XCTAssertEqual(parsed.episodes.last?.number, 4_098)
    }

    func testDetailFieldsAreBoundedWithoutRejectingLegacyPayload() throws {
        let data = try JSONSerialization.data(withJSONObject: [[
            "description": String(repeating: "d", count: 70 * 1_024),
            "aliases": String(repeating: "a", count: 10 * 1_024),
            "airdate": String(repeating: "2", count: 512)
        ]])

        let parsed = try JSController.boundedMediaItems(from: data)

        XCTAssertEqual(parsed.rawCount, 1)
        XCTAssertEqual(parsed.items.first?.description.utf8.count, 64 * 1_024)
        XCTAssertEqual(parsed.items.first?.aliases.utf8.count, 8 * 1_024)
        XCTAssertEqual(parsed.items.first?.airdate.utf8.count, 256)
    }

    func testStructuredStreamsSubtitlesAndHeadersAreBoundedAndSanitized() throws {
        var streams = (0..<1_300).map { index in
            [
                "url": "https://media.example.test/\(index).m3u8",
                "title": "Stream \(index)",
                "headers": ["X-Provider": "safe"]
            ] as [String: Any]
        }
        streams[0]["headers"] = ["Host": "private.invalid", "X-Provider": "safe"]
        streams[1]["url"] = "https://media.example.test/ok\r\nInjected: yes"
        let subtitles = (0..<300).map { "https://subs.example.test/\($0).vtt" }
        let data = try JSONSerialization.data(withJSONObject: [
            "streams": streams,
            "subtitles": subtitles
        ])

        let parsed = try JSController.boundedStreamExtractionResult(from: data)

        XCTAssertNil(parsed.streams)
        XCTAssertEqual(parsed.sources?.count, 1_200)
        XCTAssertEqual(
            (parsed.sources?.first?["headers"] as? [String: String])?["Host"],
            "private.invalid"
        )
        XCTAssertEqual(
            (parsed.sources?[1]["headers"] as? [String: String])?["X-Provider"],
            "safe"
        )
        XCTAssertEqual(parsed.subtitles?.count, 256)
    }

    func testOversizedServicePayloadsFailBeforeJSONDecode() {
        let oversized = Data(repeating: 0x20, count: 4 * 1_024 * 1_024 + 1)

        XCTAssertThrowsError(try JSController.boundedMediaItems(from: oversized))
        XCTAssertThrowsError(try JSController.boundedEpisodeLinks(from: oversized))
        XCTAssertThrowsError(try JSController.boundedStreamExtractionResult(from: oversized))
    }
}

#endif

#if os(iOS)
private actor DelayedServiceRankingWorker: ServiceResultRankingComputing {
    private struct Request {
        let titles: [String]
        let context: ServiceResultRankingContext
        var continuation: CheckedContinuation<[ServiceResultRankingContext.RankedSearchResult], Error>?
    }

    private var requests: [Request] = []
    private var submissionObservers: [(Int, @Sendable () -> Void)] = []
    var requestCount: Int { requests.count }

    func onSubmitted(_ count: Int, perform: @escaping @Sendable () -> Void) {
        if requests.count >= count {
            perform()
        } else {
            submissionObservers.append((count, perform))
        }
    }

    func rank(titles: [String], context: ServiceResultRankingContext) async throws -> [ServiceResultRankingContext.RankedSearchResult] {
        try await withCheckedThrowingContinuation { continuation in
            requests.append(Request(titles: titles, context: context, continuation: continuation))
            let ready = submissionObservers.filter { $0.0 <= requests.count }
            submissionObservers.removeAll { $0.0 <= requests.count }
            ready.forEach { $0.1() }
        }
    }

    func complete(_ index: Int) throws {
        guard requests.indices.contains(index), let continuation = requests[index].continuation else { return }
        let scores = try requests[index].context.rankedServiceResults(requests[index].titles)
        requests[index].continuation = nil
        continuation.resume(returning: scores)
    }
}

final class ServicesResolvedPlaybackHandoffTests: XCTestCase {
    private let firstURL = URL(fileURLWithPath: "/first-stream")
    private let secondURL = URL(fileURLWithPath: "/second-stream")

    func testSourceFamilyHandoffsDeliverOnceAfterIntentionalDismissal() throws {
        for source in [PlaybackSourceKind.service, .stremio, .skyStream, .nuvio] {
            var state = ServicesResolvedPlaybackHandoffState()
            let operation = try XCTUnwrap(state.begin(url: firstURL))
            var events: [String] = []
            XCTAssertTrue(state.claim(operation, isCurrent: true), source.rawValue)
            events.append("committed")
            events.append("dismissed")
            state.cancelPending()
            if state.complete(operation, isCurrent: true) == .deliver {
                events.append("resolved")
            }
            XCTAssertEqual(state.complete(operation, isCurrent: true), .ignore, source.rawValue)
            XCTAssertNil(state.begin(url: secondURL), source.rawValue)
            XCTAssertEqual(events, ["committed", "dismissed", "resolved"], source.rawValue)
        }
    }

    func testSupersededPreflightCannotClaimTheNewHandoff() throws {
        var state = ServicesResolvedPlaybackHandoffState()
        let old = try XCTUnwrap(state.begin(url: firstURL))
        let current = try XCTUnwrap(state.begin(url: secondURL))
        XCTAssertFalse(state.claim(old, isCurrent: true))
        state.cancelPending(old)
        XCTAssertTrue(state.claim(current, isCurrent: true))
        XCTAssertEqual(state.complete(old, isCurrent: true), .ignore)
        XCTAssertEqual(state.complete(current, isCurrent: true), .deliver)
    }

    func testDismissalBeforeClaimRejectsLateResultAndAllowsLaterPresentation() throws {
        var state = ServicesResolvedPlaybackHandoffState()
        let old = try XCTUnwrap(state.begin(url: firstURL))
        state.cancelPending()
        XCTAssertFalse(state.claim(old, isCurrent: true))
        XCTAssertFalse(state.retainsResource(at: firstURL))
        let current = try XCTUnwrap(state.begin(url: firstURL))
        XCTAssertNotEqual(old, current)
        XCTAssertTrue(state.claim(current, isCurrent: true))
    }

    func testOwnerChangeBeforeClaimDoesNotCommitPlayback() throws {
        var state = ServicesResolvedPlaybackHandoffState()
        let operation = try XCTUnwrap(state.begin(url: firstURL))
        XCTAssertFalse(state.claim(operation, isCurrent: false))
        state.cancelPending(operation)
        XCTAssertEqual(state.complete(operation, isCurrent: true), .ignore)
        XCTAssertFalse(state.retainsResource(at: firstURL))
    }

    func testOwnerOrWatchTogetherChangeDuringDismissalDiscardsOnce() throws {
        var state = ServicesResolvedPlaybackHandoffState()
        let operation = try XCTUnwrap(state.begin(url: firstURL))
        XCTAssertTrue(state.claim(operation, isCurrent: true))
        state.cancelPending()
        XCTAssertEqual(state.complete(operation, isCurrent: false), .discard)
        XCTAssertFalse(state.retainsResource(at: firstURL))
        XCTAssertEqual(state.complete(operation, isCurrent: true), .ignore)
        XCTAssertNil(state.begin(url: secondURL))
    }

    func testDuplicateRequestDoesNotReleasePendingOrDeliveredProxyResource() throws {
        var state = ServicesResolvedPlaybackHandoffState()
        let earlier = try XCTUnwrap(state.begin(url: firstURL))
        let operation = try XCTUnwrap(state.begin(url: firstURL))
        XCTAssertFalse(state.claim(earlier, isCurrent: true))
        state.cancelPending(earlier)
        XCTAssertTrue(state.retainsResource(at: firstURL))
        XCTAssertTrue(state.claim(operation, isCurrent: true))
        XCTAssertNil(state.begin(url: firstURL))
        XCTAssertTrue(state.retainsResource(at: firstURL))
        XCTAssertEqual(state.complete(operation, isCurrent: true), .deliver)
        XCTAssertNil(state.begin(url: firstURL))
        XCTAssertTrue(state.retainsResource(at: firstURL))
        XCTAssertFalse(state.retainsResource(at: secondURL))
    }

    func testWatchTogetherIdentityRejectsReturnToSameMediaAtLaterRevisionOrSession() {
        let sessionID = UUID()
        let original = WatchTogetherPlaybackHandoffIdentity(sessionID: sessionID, sessionGeneration: 1, mediaRevision: 4, mediaIdentifier: "episode-a")
        let changed = WatchTogetherPlaybackHandoffIdentity(sessionID: sessionID, sessionGeneration: 1, mediaRevision: 5, mediaIdentifier: "episode-b")
        let returned = WatchTogetherPlaybackHandoffIdentity(sessionID: sessionID, sessionGeneration: 1, mediaRevision: 6, mediaIdentifier: "episode-a")
        let replacement = WatchTogetherPlaybackHandoffIdentity(sessionID: UUID(), sessionGeneration: 2, mediaRevision: 4, mediaIdentifier: "episode-a")
        let rejoined = WatchTogetherPlaybackHandoffIdentity(sessionID: sessionID, sessionGeneration: 2, mediaRevision: 4, mediaIdentifier: "episode-a")
        XCTAssertNotEqual(original, changed)
        XCTAssertNotEqual(original, returned)
        XCTAssertNotEqual(original, replacement)
        XCTAssertNotEqual(original, rejoined)
    }

    func testWatchTogetherNoSessionPreviewPreservesItsLifetimeGeneration() {
        let preview = WatchTogetherPlaybackHandoffIdentity(sessionID: nil, sessionGeneration: 2, mediaRevision: nil, mediaIdentifier: nil)
        let unchanged = WatchTogetherPlaybackHandoffIdentity(sessionID: nil, sessionGeneration: 2, mediaRevision: nil, mediaIdentifier: nil)
        let afterSessionEnded = WatchTogetherPlaybackHandoffIdentity(sessionID: nil, sessionGeneration: 4, mediaRevision: nil, mediaIdentifier: nil)
        XCTAssertEqual(preview, unchanged)
        XCTAssertNotEqual(preview, afterSessionEnded)
    }

    func testSupersededPreflightAbandonmentPreservesCurrentSameURLProxy() throws {
        var state = ServicesResolvedPlaybackHandoffState()
        var invalidationCount = 0
        let ownership = PlaybackProxySessionOwnership(proxyURLs: [firstURL]) { _ in
            invalidationCount += 1
        }
        let old = try XCTUnwrap(state.begin(url: firstURL))
        let current = try XCTUnwrap(state.begin(url: firstURL))
        state.cancelPending(old)
        if !state.retainsResource(at: firstURL) { ownership.invalidate() }
        XCTAssertEqual(invalidationCount, 0)
        XCTAssertFalse(ownership.isInvalidated)
        XCTAssertTrue(state.claim(current, isCurrent: true))
        XCTAssertEqual(state.complete(current, isCurrent: false), .discard)
        if !state.retainsResource(at: firstURL) { ownership.invalidate() }
        XCTAssertEqual(invalidationCount, 1)
        XCTAssertTrue(ownership.isInvalidated)
    }
}

final class ServiceResultRankingSnapshotTests: XCTestCase {
    private enum RankingTestError: Error { case timedOut }

    private func context(
        algorithm: SimilarityAlgorithm = .hybrid,
        title: String = "Example Adventure",
        originalTitle: String? = "Example Adventure Original",
        anime: Bool = false,
        forced: Bool = false,
        minimum: Double = 0.4,
        quality: Double = 0.9,
        drop: Bool = false
    ) -> ServiceResultRankingContext {
        ServiceResultRankingContext(
            algorithm: algorithm, localeIdentifier: "en_US_POSIX",
            effectiveTitle: title, mediaTitle: title, displayTitle: title,
            originalTitle: originalTitle, seasonTitleOverride: nil,
            animeSeasonTitle: anime ? title : nil,
            normalizedAnimeSequelTitle: nil, strippedAnimeFallbackTitle: nil,
            isAnimeContent: anime, isForcedWatchTogetherAnimePlayback: forced,
            selectedEpisode: anime ? .init(seasonNumber: 2, episodeNumber: 1) : nil,
            serviceResultMinimumSimilarity: minimum, highQualityThreshold: quality,
            dropsMismatches: drop
        )
    }

    private func waitForRequests(_ count: Int, worker: DelayedServiceRankingWorker) async throws {
        let submitted = expectation(description: "Ranking worker received input \(count)")
        await worker.onSubmitted(count) { submitted.fulfill() }
        await fulfillment(of: [submitted], timeout: 5)
        guard await worker.requestCount >= count else { throw RankingTestError.timedOut }
    }

    @MainActor
    func testSnapshotPreservesStableTiesRetainedLimitAndPayloadIdentity() throws {
        let context = context()
        let results = (0..<340).map {
            SearchItem(title: "Example Adventure", imageUrl: "image-\($0)", href: "href-\($0)")
        }
        let scores = try context.rankedServiceResults(results.map(\.title))
        let snapshot = ServiceResultRankingSnapshot(results: results, scores: scores, context: context)
        XCTAssertEqual(snapshot.results.count, 300)
        XCTAssertEqual(snapshot.highQuality.count, 80)
        XCTAssertTrue(snapshot.lowQuality.isEmpty)
        XCTAssertEqual(snapshot.results.map(\.id), Array(results.prefix(300)).map(\.id))
        XCTAssertEqual(snapshot.ranked.first?.result.imageUrl, "image-0")
        XCTAssertEqual(snapshot.ranked.last?.result.href, "href-299")
    }

    @MainActor
    func testSnapshotThresholdPartitionPreservesRankAndVisibleLimit() throws {
        let context = context(minimum: 0.5, quality: 0.9, drop: true)
        let results = (0..<25).map { SearchItem(title: "Example Adventure", imageUrl: "", href: "match-\($0)") }
            + (0..<90).map { SearchItem(title: "zzzzzz \($0)", imageUrl: "", href: "other-\($0)") }
        let snapshot = ServiceResultRankingSnapshot(
            results: results, scores: try context.rankedServiceResults(results.map(\.title)), context: context
        )
        XCTAssertEqual(snapshot.highQuality.map(\.id), Array(results.prefix(25)).map(\.id))
        XCTAssertTrue(snapshot.lowQuality.allSatisfy { result in
            snapshot.ranked.first(where: { $0.result.id == result.id })?.score.initialSimilarity ?? 0 >= 0.5
        })
        XCTAssertLessThanOrEqual(snapshot.highQuality.count + snapshot.lowQuality.count, 80)
    }

    func testForcedAnimeDestinationExcludesAlternateSeasonWithoutChangingRawRanking() throws {
        let context = context(title: "Example Season 2", originalTitle: "Example Season 1", anime: true, forced: true)
        let scores = try context.rankedServiceResults(["Example Season 1", "Example Season 2 (English Dub)", "Example Season 3"])
        let destination = scores.filter(\.matchesForcedDestination)
        XCTAssertEqual(destination.map(\.index), [1])
        XCTAssertEqual(destination.first?.animeSeasonPreference, 1)
    }

    func testExplicitAlgorithmScoringIsIndependentOfTheSharedSelectedAlgorithm() {
        for algorithm in SimilarityAlgorithm.allCases {
            let actual = AlgorithmManager.calculateSimilarity(original: "abc", result: "axc", algorithm: algorithm)
            let expected: Double
            switch algorithm {
            case .hybrid: expected = HybridSimilarity.calculateSimilarity(original: "abc", result: "axc")
            case .jaroWinkler: expected = JaroWinklerSimilarity.calculateSimilarity(original: "abc", result: "axc")
            case .levenshtein: expected = LevenshteinDistance.calculateSimilarity(original: "abc", result: "axc")
            }
            XCTAssertEqual(actual, expected, accuracy: 0.000_000_1)
        }
    }

    @MainActor
    func testPendingRankingIsAwaitedBeforeAutomaticSelectionCanReadIt() async throws {
        let worker = DelayedServiceRankingWorker()
        let model = ModulesSearchResultsViewModel(rankingWorker: worker)
        let serviceID = UUID()
        let result = SearchItem(title: "Example Adventure", imageUrl: "image", href: "href")
        model.updateRankingContext(context())
        model.enqueueServiceResults([result], serviceID: serviceID, merging: false)
        try await waitForRequests(1, worker: worker)
        var completed = false
        let selection = Task { @MainActor in
            let snapshot = await model.awaitServiceRanking(serviceID)
            completed = true
            return snapshot
        }
        for _ in 0..<10 { await Task.yield() }
        XCTAssertFalse(completed)
        XCTAssertTrue(model.pendingServiceRankings.contains(serviceID))
        try await worker.complete(0)
        let snapshot = await selection.value
        XCTAssertEqual(snapshot?.ranked.first?.result.id, result.id)
        XCTAssertFalse(model.pendingServiceRankings.contains(serviceID))
    }

    @MainActor
    func testNewContextCannotPublishOldAlgorithmOrThresholdScores() async throws {
        let worker = DelayedServiceRankingWorker()
        let model = ModulesSearchResultsViewModel(rankingWorker: worker)
        let serviceID = UUID()
        model.updateRankingContext(context(algorithm: .hybrid))
        model.enqueueServiceResults([SearchItem(title: "Example", imageUrl: "", href: "one")], serviceID: serviceID, merging: false)
        try await waitForRequests(1, worker: worker)
        let replacement = context(algorithm: .levenshtein, minimum: 0.95, quality: 0.99, drop: true)
        model.updateRankingContext(replacement)
        try await worker.complete(0)
        try await waitForRequests(2, worker: worker)
        XCTAssertNil(model.currentServiceRankingSnapshot(for: serviceID))
        try await worker.complete(1)
        let snapshot = await model.awaitServiceRanking(serviceID)
        XCTAssertEqual(snapshot?.context, replacement)
        XCTAssertTrue(snapshot?.highQuality.isEmpty == true)
        XCTAssertTrue(snapshot?.lowQuality.isEmpty == true)
    }

    @MainActor
    func testMergedPublicationWaitsForPriorRetentionAndKeepsOriginalDuplicatePayload() async throws {
        let worker = DelayedServiceRankingWorker()
        let model = ModulesSearchResultsViewModel(rankingWorker: worker)
        let serviceID = UUID()
        let first = SearchItem(title: "Example Adventure", imageUrl: "original", href: "same")
        let duplicate = SearchItem(title: "Different", imageUrl: "replacement", href: "same")
        let second = SearchItem(title: "Example Adventure Season 2", imageUrl: "second", href: "second")
        model.updateRankingContext(context())
        model.enqueueServiceResults([first], serviceID: serviceID, merging: false)
        try await waitForRequests(1, worker: worker)
        model.enqueueServiceResults([duplicate, second], serviceID: serviceID, merging: true)
        try await worker.complete(0)
        try await waitForRequests(2, worker: worker)
        try await worker.complete(1)
        let snapshot = await model.awaitServiceRanking(serviceID)
        XCTAssertEqual(snapshot?.results.map(\.id), [first.id, second.id])
        XCTAssertEqual(snapshot?.results.first?.imageUrl, "original")
        XCTAssertEqual(model.serviceRankingRevision, 1)
    }

    @MainActor
    func testPauseMarksUnpublishedSearchForRestartAndRejectsLateCompletion() async throws {
        let worker = DelayedServiceRankingWorker()
        let model = ModulesSearchResultsViewModel(rankingWorker: worker)
        let serviceID = UUID()
        model.updateRankingContext(context())
        model.enqueueServiceResults([SearchItem(title: "Example Adventure", imageUrl: "", href: "old")], serviceID: serviceID, merging: false)
        try await waitForRequests(1, worker: worker)
        model.isSearching = false
        model.cancelServiceRankings()
        XCTAssertTrue(model.isSearching)
        try await worker.complete(0)
        let stale = await model.awaitServiceRanking(serviceID)
        XCTAssertNil(stale)
        XCTAssertNil(model.moduleResults[serviceID])
    }

    @MainActor
    func testAccountEpochRejectsPendingAndCompletedSnapshotsWithoutGlobalNotifications() async throws {
        let worker = DelayedServiceRankingWorker()
        let epoch = MediaStateCaptureMutationClock()
        let model = ModulesSearchResultsViewModel(rankingWorker: worker, rankingAccountClock: epoch)
        let serviceID = UUID()
        model.updateRankingContext(context())
        model.enqueueServiceResults([SearchItem(title: "Example Adventure", imageUrl: "", href: "first")], serviceID: serviceID, merging: false)
        try await waitForRequests(1, worker: worker)
        try await worker.complete(0)
        let completed = await model.awaitServiceRanking(serviceID)
        XCTAssertNotNil(completed)
        epoch.advance()
        XCTAssertNil(model.currentServiceRankingSnapshot(for: serviceID))
        model.enqueueServiceResults([SearchItem(title: "Example Adventure", imageUrl: "", href: "second")], serviceID: serviceID, merging: false)
        try await waitForRequests(2, worker: worker)
        epoch.advance()
        try await worker.complete(1)
        let stale = await model.awaitServiceRanking(serviceID)
        XCTAssertNil(stale)
    }
}
#endif
