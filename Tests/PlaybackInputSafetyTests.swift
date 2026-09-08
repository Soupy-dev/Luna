import XCTest
import SwiftUI
import Combine
@testable import Eclipse

private struct ServicesSheetInactiveSceneFixture: View {
    @Environment(\.scenePhase) private var scenePhase
    let onAppear: (Bool) -> Void
    let onScene: (ObjectIdentifier?, Bool) -> Void

    var body: some View {
        ServicesSheetPresentationAnchor(onResolve: { _ in }, onSceneActivity: onScene)
            .onAppear { onAppear(scenePhase == .active) }
    }
}

final class PlaybackInputSafetyTests: XCTestCase {
    func testActiveOwningSceneStartsWorkWhenSwiftUIRemainsInactive() {
        let owner = NSObject()
        var state = ServicesSheetActivityState()
        XCTAssertEqual(state.appear(environmentIsActive: false), .none)
        XCTAssertFalse(state.hasStarted)
        XCTAssertEqual(state.updateScene(id: ObjectIdentifier(owner), isActive: true), .start)
        XCTAssertTrue(state.allowsWork)
        XCTAssertEqual(state.updateEnvironment(isActive: false), .none)
        XCTAssertEqual(state.updateScene(id: ObjectIdentifier(owner), isActive: true), .none)
        XCTAssertEqual(state.appear(environmentIsActive: false), .none)
    }

    func testOwningScenePausesResumesAndIgnoresOtherWindows() {
        let owner = NSObject()
        let other = NSObject()
        var state = ServicesSheetActivityState()
        XCTAssertEqual(state.updateScene(id: ObjectIdentifier(owner), isActive: false), .none)
        XCTAssertEqual(state.appear(environmentIsActive: true), .none)
        XCTAssertEqual(state.sceneActivityChanged(id: ObjectIdentifier(other), isActive: true), .none)
        XCTAssertFalse(state.allowsWork)
        XCTAssertEqual(state.sceneActivityChanged(id: ObjectIdentifier(owner), isActive: true), .start)
        XCTAssertEqual(state.sceneActivityChanged(id: ObjectIdentifier(owner), isActive: false), .pause)
        XCTAssertEqual(state.updateEnvironment(isActive: true), .none)
        XCTAssertEqual(state.sceneActivityChanged(id: ObjectIdentifier(owner), isActive: true), .resume)
        XCTAssertEqual(state.updateScene(id: nil, isActive: false), .pause)
        XCTAssertEqual(state.updateEnvironment(isActive: true), .none)
        XCTAssertEqual(state.sceneActivityChanged(id: ObjectIdentifier(owner), isActive: true), .none)
    }

    func testDismissedSheetCannotRestartFromLateActivation() {
        let owner = NSObject()
        var state = ServicesSheetActivityState()
        XCTAssertEqual(state.appear(environmentIsActive: true), .start)
        state.dismiss()
        XCTAssertEqual(state.updateScene(id: ObjectIdentifier(owner), isActive: true), .none)
        XCTAssertEqual(state.updateEnvironment(isActive: true), .none)
        XCTAssertEqual(state.appear(environmentIsActive: true), .none)
        XCTAssertFalse(state.isPresented)
    }

    func testSheetResumesAfterReturningFromAChildPresentation() {
        let owner = NSObject()
        var state = ServicesSheetActivityState()
        _ = state.updateScene(id: ObjectIdentifier(owner), isActive: true)
        XCTAssertEqual(state.appear(environmentIsActive: false), .start)
        XCTAssertEqual(state.disappear(), .pause)
        XCTAssertEqual(state.updateScene(id: ObjectIdentifier(owner), isActive: true), .none)
        XCTAssertEqual(state.appear(environmentIsActive: false), .resume)
        XCTAssertEqual(state.appear(environmentIsActive: false), .none)
        state.dismiss()
        _ = state.disappear()
        XCTAssertEqual(state.appear(environmentIsActive: false), .none)
    }

    @MainActor
    func testUIKitHostingAnchorReportsActiveSceneDespiteInactiveEnvironment() async throws {
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }) else {
            throw XCTSkip("The test host has no active window scene")
        }
        let started = expectation(description: "Attached scene starts the inactive-environment sheet")
        var state = ServicesSheetActivityState()
        var fulfilled = false
        var observationFinished = false
        func checkStarted() {
            if state.hasStarted && !fulfilled {
                fulfilled = true
                started.fulfill()
            }
        }
        let fixture = ServicesSheetInactiveSceneFixture(
            onAppear: { active in
                guard !observationFinished else { return }
                XCTAssertFalse(active)
                _ = state.appear(environmentIsActive: active)
                checkStarted()
            },
            onScene: { sceneID, active in
                guard !observationFinished else { return }
                if let sceneID { XCTAssertEqual(sceneID, ObjectIdentifier(scene)) }
                _ = state.updateScene(id: sceneID, isActive: active)
                checkStarted()
            }
        ).environment(\.scenePhase, .inactive)
        let window = UIWindow(windowScene: scene)
        window.rootViewController = UIHostingController(rootView: fixture)
        window.isHidden = false
        defer {
            observationFinished = true
            window.isHidden = true
            window.rootViewController = nil
        }
        await fulfillment(of: [started], timeout: 3)
        XCTAssertTrue(state.allowsWork)
    }

    func testServiceSettingOptionsKeepSingleQuotesWithoutTrapping() throws {
        for quote in ["\"", "'", "“", "”", "‘", "’"] {
            let source = [
                "// Settings start",
                "const mode = \"auto\"; // Select mode [\(quote), \"auto\", '', ‘manual’]",
                "// Settings end"
            ].joined(separator: "\n")
            let setting = try XCTUnwrap(ServiceManager.parseSettingsFromJS(source).first)
            XCTAssertEqual(setting.options, [quote, "auto", "manual"])
            XCTAssertEqual(setting.comment, "Select mode")
            XCTAssertEqual(setting.value, "auto")
        }
    }

    func testServiceSettingTypesAndRoundTripRemainUnchanged() {
        let source = [
            "const untouched = 7;",
            "// Settings start",
            "const text = ‘hello’; // Label [‘hello’, “world”]",
            "const enabled = true;",
            "const count = 12;",
            "const speed = 1.5;",
            "// Settings end",
            "function useSettings() { return untouched; }"
        ].joined(separator: "\n")
        let settings = ServiceManager.parseSettingsFromJS(source)
        XCTAssertEqual(settings.map(\.value), ["hello", "true", "12", "1.5"])
        XCTAssertEqual(settings.map(\.type), [.string, .bool, .int, .float])
        let updated = ServiceManager.updateSettingsInJS(source, with: settings)
        XCTAssertTrue(updated.hasPrefix("const untouched = 7;\n"))
        XCTAssertTrue(updated.hasSuffix("function useSettings() { return untouched; }"))
        XCTAssertEqual(ServiceManager.parseSettingsFromJS(updated).map(\.value), settings.map(\.value))
    }

    @MainActor
    func testTraktWatchlistBatchPersistsOnceAndPreservesExistingEntries() async throws {
        let profile = UUID()
        let key = LibraryManager.collectionsKey(for: profile)
        defer { UserDefaults.standard.removeObject(forKey: key) }
        let manager = LibraryManager(profileID: profile)
        manager.applyTraktWatchlistPull([watchlistResult(1)])
        let collection = try XCTUnwrap(manager.collections.first { $0.name == TrackerManager.traktWatchlistCollectionName })
        let originalID = collection.id
        let originalDate = Date(timeIntervalSince1970: 1234)
        collection.items = [
            LibraryItem(searchResult: watchlistResult(1), dateAdded: originalDate),
            LibraryItem(searchResult: watchlistResult(1), dateAdded: originalDate)
        ]
        await drainLibraryCallbacks()
        var publications = 0
        var saves = 0
        let subscription = collection.objectWillChange.sink { publications += 1 }
        let observer = NotificationCenter.default.addObserver(forName: .libraryDataDidChange, object: manager, queue: nil) { _ in
            saves += 1
        }
        defer {
            subscription.cancel()
            NotificationCenter.default.removeObserver(observer)
        }
        let results = (1...500).map(watchlistResult)
        manager.applyTraktWatchlistPull(results + results)
        await drainLibraryCallbacks()
        XCTAssertEqual(collection.id, originalID)
        XCTAssertEqual(collection.items.count, 501)
        XCTAssertEqual(Array(collection.items.prefix(2)).map(\.dateAdded), [originalDate, originalDate])
        XCTAssertEqual(Array(collection.items.dropFirst(2)).map { $0.searchResult.id }, Array(2...500))
        XCTAssertEqual(publications, 1)
        XCTAssertEqual(saves, 1)
        manager.applyTraktWatchlistPull(results)
        await drainLibraryCallbacks()
        XCTAssertEqual(publications, 1)
        XCTAssertEqual(saves, 1)
    }

    @MainActor
    func testTraktWatchlistDoesNotOverwriteUnreadableStore() {
        let profile = UUID()
        let key = LibraryManager.collectionsKey(for: profile)
        let original = Data("unreadable library".utf8)
        UserDefaults.standard.set(original, forKey: key)
        defer { UserDefaults.standard.removeObject(forKey: key) }
        let manager = LibraryManager(profileID: profile)
        manager.applyTraktWatchlistPull([watchlistResult(1)])
        XCTAssertEqual(UserDefaults.standard.data(forKey: key), original)
        XCTAssertFalse(manager.collections.contains { $0.name == TrackerManager.traktWatchlistCollectionName })
    }

    private func watchlistResult(_ id: Int) -> TMDBSearchResult {
        TMDBSearchResult(id: id, mediaType: "tv", title: nil, name: "Title \(id)", overview: nil,
                         posterPath: nil, backdropPath: nil, releaseDate: nil, firstAirDate: nil,
                         voteAverage: nil, popularity: 0, adult: false, genreIds: nil)
    }

    @MainActor
    private func drainLibraryCallbacks() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }
    func testSkipSegmentKeysRejectUnrepresentableTimes() {
        for value in [Double.nan, .infinity, -.infinity, -1, Double(Int.max), .greatestFiniteMagnitude] {
            XCTAssertEqual(SkipSegment(startTime: value, endTime: value, type: .intro).uniqueKey, "intro_unknown")
        }
        XCTAssertEqual(SkipSegment(startTime: 12.9, endTime: 90, type: .intro).uniqueKey, "intro_12")
        XCTAssertEqual(SkipSegment(startTime: 0, endTime: 90, type: .recap).uniqueKey, "recap_0")
    }

    func testAniSkipDurationHandlesUnknownAndOutOfRangeRendererValues() {
        for value in [Double.nan, .infinity, -.infinity, -1, 0, Double(Int.max), .greatestFiniteMagnitude] {
            XCTAssertEqual(AniSkipService.episodeLengthParameter(for: value), 0)
        }
        XCTAssertEqual(AniSkipService.episodeLengthParameter(for: 1440.75), 1440)
        XCTAssertEqual(AniSkipService.episodeLengthParameter(for: Double(Int.max).nextDown), Int.max - 1023)
    }

    func testAVPlayerResponseRejectsUnrepresentableAndMalformedByteRanges() throws {
        let invalidRanges = [
            "bytes 9223372036854775807-9223372036854775807/*",
            "bytes 9223372036854775806-9223372036854775807/*",
            "bytes 0-9223372036854775808/*",
            "bytes 0-1/9223372036854775808",
            "bytes -1-1/2",
            "bytes +0-1/2",
            "bytes 2-1/3",
            "bytes 0-1/1",
            "bytes 0-1/0",
            "bytes 0-1/unknown",
            "bytes 0-/2",
            "bytes 0-1/",
            "bytes 0-1/2/3",
            "bytes */2",
            "items 0-1/2"
        ]
        for range in invalidRanges {
            let response = try makeResponse(status: 206, headers: [
                "Content-Range": range,
                "Content-Length": "1"
            ])
            XCTAssertNil(AVPlayerResourceLoader.responseByteLayout(response, requestedOffset: 0), range)
        }
    }

    func testAVPlayerResponseKeepsValidPartialAndUnknownLengthRanges() throws {
        let partial = try makeResponse(status: 206, headers: [
            "Content-Range": "bytes 100-199/1000",
            "Content-Length": "100"
        ])
        let partialLayout = try XCTUnwrap(AVPlayerResourceLoader.responseByteLayout(partial, requestedOffset: 100))
        XCTAssertEqual(partialLayout.start, 100)
        XCTAssertEqual(partialLayout.totalLength, 1000)

        let unknown = try makeResponse(status: 206, headers: ["Content-Range": "Bytes 100-199/*"])
        let unknownLayout = try XCTUnwrap(AVPlayerResourceLoader.responseByteLayout(unknown, requestedOffset: 100))
        XCTAssertEqual(unknownLayout.start, 100)
        XCTAssertEqual(unknownLayout.totalLength, 200)

        let boundary = try makeResponse(status: 206, headers: [
            "Content-Range": "bytes 9223372036854775806-9223372036854775806/9223372036854775807",
            "Content-Length": "1"
        ])
        let boundaryLayout = try XCTUnwrap(AVPlayerResourceLoader.responseByteLayout(boundary, requestedOffset: Int64.max - 1))
        XCTAssertEqual(boundaryLayout.start, Int64.max - 1)
        XCTAssertEqual(boundaryLayout.totalLength, Int64.max)
    }

    func testAVPlayerResponsePreservesFullResponsesAndMissingRangeFallback() throws {
        let full = try makeResponse(status: 200, headers: ["Content-Length": "1000"])
        let fullLayout = try XCTUnwrap(AVPlayerResourceLoader.responseByteLayout(full, requestedOffset: 100))
        XCTAssertEqual(fullLayout.start, 0)
        XCTAssertEqual(fullLayout.totalLength, 1000)

        let partial = try makeResponse(status: 206, headers: ["Content-Length": "100"])
        let partialLayout = try XCTUnwrap(AVPlayerResourceLoader.responseByteLayout(partial, requestedOffset: 100))
        XCTAssertEqual(partialLayout.start, 100)
        XCTAssertEqual(partialLayout.totalLength, 200)
        XCTAssertNil(AVPlayerResourceLoader.responseByteLayout(partial, requestedOffset: Int64.max))

        let streaming = try makeResponse(status: 200, headers: [:])
        let streamingLayout = try XCTUnwrap(AVPlayerResourceLoader.responseByteLayout(streaming, requestedOffset: 0))
        XCTAssertEqual(streamingLayout.start, 0)
        XCTAssertEqual(streamingLayout.totalLength, 0)
    }

    func testAVPlayerResponseRejectsOverflowingLengthEvenWithARepresentableRange() throws {
        let response = try makeResponse(status: 206, headers: [
            "Content-Range": "bytes 9223372036854775806-9223372036854775806/9223372036854775807",
            "Content-Length": "2"
        ])
        XCTAssertNil(AVPlayerResourceLoader.responseByteLayout(response, requestedOffset: Int64.max - 1))
    }

    func testAVPlayerBodyChunkOffsetsRemainSafeAcrossStreamedChunks() {
        XCTAssertEqual(AVPlayerResourceLoader.bodyChunkRange(responseOffset: 100, receivedBytes: 0, chunkByteCount: 20), 100..<120)
        XCTAssertEqual(AVPlayerResourceLoader.bodyChunkRange(responseOffset: 100, receivedBytes: 20, chunkByteCount: 80), 120..<200)
        XCTAssertEqual(AVPlayerResourceLoader.bodyChunkRange(responseOffset: Int64.max - 1, receivedBytes: 0, chunkByteCount: 1), (Int64.max - 1)..<Int64.max)
        XCTAssertNil(AVPlayerResourceLoader.bodyChunkRange(responseOffset: Int64.max, receivedBytes: 0, chunkByteCount: 1))
        XCTAssertNil(AVPlayerResourceLoader.bodyChunkRange(responseOffset: Int64.max, receivedBytes: 1, chunkByteCount: 0))
        XCTAssertNil(AVPlayerResourceLoader.bodyChunkRange(responseOffset: -1, receivedBytes: 0, chunkByteCount: 1))
        XCTAssertNil(AVPlayerResourceLoader.bodyChunkRange(responseOffset: 0, receivedBytes: -1, chunkByteCount: 1))
        XCTAssertNil(AVPlayerResourceLoader.bodyChunkRange(responseOffset: 0, receivedBytes: 0, chunkByteCount: -1))
    }

    private func makeResponse(status: Int, headers: [String: String]) throws -> HTTPURLResponse {
        let url = try XCTUnwrap(URL(string: "https://example.invalid/media.mp4"))
        return try XCTUnwrap(HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers))
    }
}

final class PlaybackSubtitlePrefetchPolicyTests: XCTestCase {
    private typealias Policy = PlaybackSubtitlePrefetchPolicy

    private func resolve(
        _ candidates: [Policy.Candidate],
        sources: Set<Policy.Source> = [.addon, .openSubtitles],
        subtitles: Bool = true,
        fallback: Bool = true,
        warmup: Bool = true,
        menu: Bool = false,
        constrained: Bool = false
    ) -> [String] {
        Policy.urls(
            candidates: candidates,
            enabledSources: sources,
            subtitlesEnabled: subtitles,
            automaticFallbackEnabled: fallback,
            warmupEnabled: warmup,
            menuIsOpen: menu,
            resourceConstrained: constrained
        )
    }

    func testAutomaticPreparationRespectsEachExistingSetting() {
        let candidates = [Policy.Candidate(url: "https://example.invalid/en.srt", source: .addon, matchesPreferredLanguage: true)]
        XCTAssertEqual(resolve(candidates), [candidates[0].url])
        XCTAssertTrue(resolve(candidates, subtitles: false).isEmpty)
        XCTAssertTrue(resolve(candidates, fallback: false).isEmpty)
        XCTAssertTrue(resolve(candidates, warmup: false).isEmpty)
    }

    func testOpeningMenuCanPrepareOtherLanguagesWithoutEnablingSubtitles() {
        let candidates = [Policy.Candidate(url: "https://example.invalid/fr.srt", source: .addon, matchesPreferredLanguage: false)]
        XCTAssertTrue(resolve(candidates).isEmpty)
        XCTAssertEqual(resolve(candidates, subtitles: false, fallback: false, warmup: false, menu: true), [candidates[0].url])
    }

    func testDisabledSourcesStayDisabledEvenWithMenuOpen() {
        let candidates = [
            Policy.Candidate(url: "https://example.invalid/addon.srt", source: .addon, matchesPreferredLanguage: true),
            Policy.Candidate(url: "https://example.invalid/open.srt", source: .openSubtitles, matchesPreferredLanguage: true)
        ]
        XCTAssertEqual(resolve(candidates, sources: [.openSubtitles], menu: true), [candidates[1].url])
        XCTAssertEqual(resolve(candidates, sources: [.addon], menu: true), [candidates[0].url])
        XCTAssertTrue(resolve(candidates, sources: [], menu: true).isEmpty)
    }

    func testPreparationIsBoundedPerSourceAndUsesExactURLIdentity() {
        let candidates = [
            Policy.Candidate(url: "https://example.invalid/Sub.srt?token=A", source: .addon, matchesPreferredLanguage: true),
            Policy.Candidate(url: "https://example.invalid/Sub.srt?token=A", source: .addon, matchesPreferredLanguage: true),
            Policy.Candidate(url: "https://example.invalid/sub.srt?token=A", source: .addon, matchesPreferredLanguage: true),
            Policy.Candidate(url: "https://example.invalid/third.srt", source: .addon, matchesPreferredLanguage: true),
            Policy.Candidate(url: "https://example.invalid/Sub.srt?token=B", source: .openSubtitles, matchesPreferredLanguage: true),
            Policy.Candidate(url: "https://example.invalid/fourth.srt", source: .openSubtitles, matchesPreferredLanguage: true),
            Policy.Candidate(url: "https://example.invalid/fifth.srt", source: .openSubtitles, matchesPreferredLanguage: true)
        ]
        XCTAssertEqual(resolve(candidates), [candidates[0].url, candidates[2].url, candidates[4].url, candidates[5].url])
    }

    func testInvalidAndLocalURLsDoNotConsumePreparationSlots() {
        let candidates = ["file:///tmp/a.srt", "magnet:?xt=anything", "https:///", "https://example.invalid/a.srt"]
            .map { Policy.Candidate(url: $0, source: .addon, matchesPreferredLanguage: true) }
        XCTAssertEqual(resolve(candidates), ["https://example.invalid/a.srt"])
    }

    func testResourcePressureSuppressesAutomaticAndMenuPreparation() {
        let candidates = [Policy.Candidate(url: "https://example.invalid/en.srt", source: .addon, matchesPreferredLanguage: true)]
        XCTAssertTrue(resolve(candidates, constrained: true).isEmpty)
        XCTAssertTrue(resolve(candidates, menu: true, constrained: true).isEmpty)
    }
}
