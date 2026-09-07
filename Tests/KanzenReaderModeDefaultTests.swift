import XCTest
@testable import Eclipse

#if os(iOS)

final class KanzenReaderModeDefaultTests: XCTestCase {

    private var suiteNames: [String] = []

    private func makeStore() -> UserDefaults {
        let name = "KanzenReaderModeDefaultTests.\(UUID().uuidString)"
        suiteNames.append(name)
        guard let store = UserDefaults(suiteName: name) else {
            XCTFail("could not create an isolated defaults suite")
            return .standard
        }
        return store
    }

    override func tearDown() {
        for name in suiteNames {
            UserDefaults.standard.removePersistentDomain(forName: name)
        }
        suiteNames.removeAll()
        super.tearDown()
    }

    func testFreshProfileReadsAsContinuousScrollRatherThanLeftToRight() {
        let empty = makeStore()
        let resolution = KanzenReaderMode.resolveDefault(
            scopedKey: "kanzenReaderMode",
            stores: [empty]
        )
        XCTAssertEqual(
            resolution.mode,
            .webtoon,
            "an absent reading mode must not resolve through integer(forKey:) == 0 to LTR paging"
        )
        XCTAssertFalse(
            resolution.recoveredStoredPreference,
            "an unresolved default must never be persisted as if it were the user's choice"
        )
    }

    func testExplicitlyStoredLegacyModesStillResolve() {
        let cases: [(Int, KanzenReaderMode)] = [
            (ReadingMode.LTR.rawValue, .ltr),
            (ReadingMode.RTL.rawValue, .rtl),
            (ReadingMode.WEBTOON.rawValue, .webtoon),
            (ReadingMode.VERTICAL.rawValue, .vertical)
        ]
        for (raw, expected) in cases {
            let store = makeStore()
            store.set(raw, forKey: "readingMode")
            let resolution = KanzenReaderMode.resolveDefault(
                scopedKey: "kanzenReaderMode",
                stores: [store]
            )
            XCTAssertEqual(resolution.mode, expected, "legacy readingMode \(raw) did not round-trip")
            XCTAssertTrue(resolution.recoveredStoredPreference)
        }
    }

    func testDeviceLevelPreferenceSurvivesTheMoveToProfileScopedStorage() {
        let profile = makeStore()
        let device = makeStore()
        device.set(KanzenReaderMode.rtl.rawValue, forKey: "kanzenReaderMode")

        let resolution = KanzenReaderMode.resolveDefault(
            scopedKey: "kanzenReaderMode",
            stores: [profile, device]
        )
        XCTAssertEqual(
            resolution.mode,
            .rtl,
            "a preference written before reader mode became profile-scoped must still be found"
        )
        XCTAssertTrue(resolution.recoveredStoredPreference)
    }

    func testProfileValueWinsOverDeviceValue() {
        let profile = makeStore()
        let device = makeStore()
        profile.set(KanzenReaderMode.webtoon.rawValue, forKey: "kanzenReaderMode")
        device.set(KanzenReaderMode.ltr.rawValue, forKey: "kanzenReaderMode")

        XCTAssertEqual(
            KanzenReaderMode.resolveDefault(scopedKey: "kanzenReaderMode", stores: [profile, device]).mode,
            .webtoon
        )
    }

    func testPerSeriesOverrideBeatsTheGlobalPreference() {
        let profile = makeStore()
        profile.set(KanzenReaderMode.webtoon.rawValue, forKey: "kanzenReaderMode")
        profile.set(KanzenReaderMode.rtl.rawValue, forKey: "kanzenReaderMode.series-42")

        let resolution = KanzenReaderMode.resolveDefault(
            scopedKey: "kanzenReaderMode.series-42",
            stores: [profile]
        )
        XCTAssertEqual(resolution.mode, .rtl)
        XCTAssertFalse(
            resolution.recoveredStoredPreference,
            "a per-series override must not be copied onto the global preference"
        )
    }

    func testManufacturedLeftToRightIsRecognizedAndDeliberateChoicesAreNot() {
        let poisoned = makeStore()
        poisoned.set(KanzenReaderMode.ltr.rawValue, forKey: "kanzenReaderMode")
        XCTAssertTrue(
            KanzenReaderMode.storedGlobalDefaultIsManufactured(in: poisoned),
            "kanzenReaderMode=ltr with no readingMode is the pre-fix default path's fingerprint"
        )

        let deliberate = makeStore()
        deliberate.set(KanzenReaderMode.ltr.rawValue, forKey: "kanzenReaderMode")
        deliberate.set(ReadingMode.LTR.rawValue, forKey: "readingMode")
        XCTAssertFalse(
            KanzenReaderMode.storedGlobalDefaultIsManufactured(in: deliberate),
            "a real selection writes both keys and must never be discarded"
        )

        for mode in [KanzenReaderMode.rtl, .webtoon, .vertical] {
            let other = makeStore()
            other.set(mode.rawValue, forKey: "kanzenReaderMode")
            XCTAssertFalse(
                KanzenReaderMode.storedGlobalDefaultIsManufactured(in: other),
                "the pre-fix path could not manufacture \(mode.rawValue) with readingMode absent"
            )
        }

        let untouched = makeStore()
        XCTAssertFalse(KanzenReaderMode.storedGlobalDefaultIsManufactured(in: untouched))
    }

    func testUnrecognizedStoredValuesFallBackToTheBuiltInDefault() {
        let store = makeStore()
        store.set("sideways", forKey: "kanzenReaderMode")
        store.set(99, forKey: "readingMode")

        XCTAssertEqual(
            KanzenReaderMode.resolveDefault(scopedKey: "kanzenReaderMode", stores: [store]).mode,
            KanzenReaderMode.builtInDefault
        )
    }

    func testLegacyBackupSanitizesNovelColorPresetBeforeItCanIndexThePalette() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        for value in [Int.min, -1, 0, 1, 2, 3, 4, 5, Int.max] {
            let data = try JSONSerialization.data(withJSONObject: [
                "version": "1.0",
                "createdDate": "2026-09-05T00:00:00Z",
                "readerColorPreset": value
            ])
            let backup = try decoder.decode(BackupData.self, from: data)
            XCTAssertEqual(backup.readerColorPreset, (0...4).contains(value) ? value : 0)
            XCTAssertTrue(backup.topLevelSettingIsAuthoritative(storageKey: "readerColorPreset"))
        }
    }

    func testBackupEncodingCannotExportAnInvalidNovelColorPreset() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var backup = try decoder.decode(
            BackupData.self,
            from: Data(#"{"createdDate":"2026-09-05T00:00:00Z","readerColorPreset":4}"#.utf8)
        )
        backup.readerColorPreset = Int.max
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let restored = try decoder.decode(BackupData.self, from: encoder.encode(backup))
        XCTAssertEqual(restored.readerColorPreset, 0)
    }

    func testSequentialUnreadCountMatchesExistingChapterIdentityRules() {
        let readSets: [Set<String>] = [
            [],
            ["1", "Chapter 1", "01", "1.0", "2.5", "0", "-1"],
            ["Chapter 4 - revision 2", "Vol 1 Chapter 2", "Episode 3", "7 Extra", "Extra"],
            Set((1...100).map(String.init))
        ]
        for total in [1, 7, 100] {
            let item = MangaLibraryItem(aniListId: 1, title: "Reader probe", totalChapters: total)
            for read in readSets {
                let keys = Set(read.map(ChapterIdentityNormalizer.key))
                let expected = (1...total).filter {
                    !keys.contains(ChapterIdentityNormalizer.key(for: String($0)))
                }.count
                XCTAssertEqual(item.unreadCount(readChapters: read), expected)
            }
        }
    }

    func testUntrustedLargeChapterTotalsDoNotRequireEnumeratingChapters() throws {
        let data = try JSONSerialization.data(withJSONObject: [
            "aniListId": 1,
            "title": "Reader probe",
            "totalChapters": Int.max,
            "dateAdded": "2026-09-05T00:00:00Z"
        ])
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let item = try decoder.decode(MangaLibraryItem.self, from: data)
        XCTAssertEqual(item.unreadCount(readChapters: []), Int.max)
        XCTAssertEqual(item.unreadCount(readChapters: ["1", "Chapter 1", "2", "2.5", "Vol 1 Chapter 3"]), Int.max - 2)
    }

    func testSourceChapterNumbersRetainFractionalAndVolumeSpecificIdentity() {
        let item = MangaLibraryItem(
            aniListId: 1,
            title: "Reader probe",
            totalChapters: Int.max,
            latestChapterNumbers: ["1", "1.0", "2.5", "Vol 1 Chapter 2", "Extra"]
        )
        XCTAssertEqual(item.unreadCount(readChapters: ["Chapter 1", "2.5"]), 2)
        XCTAssertEqual(MangaLibraryItem(aniListId: 1, title: "Reader probe", totalChapters: -1).unreadCount(readChapters: ["1"]), 0)
    }

    func testTrackerMangaExpansionRejectsUnboundedCountsWithoutTruncation() {
        XCTAssertTrue(TrackerRemoteProgressBoundary.canExpandMangaProgress(0))
        XCTAssertTrue(TrackerRemoteProgressBoundary.canExpandMangaProgress(100_000))
        XCTAssertFalse(TrackerRemoteProgressBoundary.canExpandMangaProgress(100_001))
        XCTAssertFalse(TrackerRemoteProgressBoundary.canExpandMangaProgress(Int.max))
        XCTAssertFalse(TrackerRemoteProgressBoundary.canExpandMangaProgress(-1))
    }

    func testMangaPaginationRejectsRepeatedMALContinuation() throws {
        var sequence = TrackerRemoteProgressBoundary.PageSequence()
        let first = try XCTUnwrap(URL(string: "https://api.myanimelist.net/v2/users/@me/mangalist?offset=0"))
        let second = try XCTUnwrap(URL(string: "https://api.myanimelist.net/v2/users/@me/mangalist?offset=1000"))
        let third = try XCTUnwrap(URL(string: "https://api.myanimelist.net/v2/users/@me/mangalist?offset=2000"))

        XCTAssertTrue(sequence.beginMALPage(first, listKind: .manga))
        XCTAssertTrue(sequence.allowsMALContinuation(second, listKind: .manga))
        XCTAssertTrue(sequence.beginMALPage(second, listKind: .manga))
        XCTAssertFalse(sequence.allowsMALContinuation(first, listKind: .manga))
        XCTAssertFalse(sequence.beginMALPage(first, listKind: .manga))
        XCTAssertFalse(sequence.beginMALPage(second, listKind: .manga))
        XCTAssertTrue(sequence.beginMALPage(third, listKind: .manga))
    }

    func testMangaPaginationUsesExistingPageLimitForUniqueURLsAndChunks() throws {
        var malSequence = TrackerRemoteProgressBoundary.PageSequence()
        var aniListSequence = TrackerRemoteProgressBoundary.PageSequence()
        for offset in 0..<1_000 {
            let url = try XCTUnwrap(URL(string: "https://api.myanimelist.net/v2/users/@me/mangalist?offset=\(offset)"))
            XCTAssertTrue(malSequence.beginMALPage(url, listKind: .manga))
            XCTAssertTrue(aniListSequence.beginPage())
        }
        let beyondLimit = try XCTUnwrap(URL(string: "https://api.myanimelist.net/v2/users/@me/mangalist?offset=1000"))
        XCTAssertFalse(malSequence.allowsMALContinuation(beyondLimit, listKind: .manga))
        XCTAssertFalse(malSequence.beginMALPage(beyondLimit, listKind: .manga))
        XCTAssertFalse(aniListSequence.canRequestNextPage)
        XCTAssertFalse(aniListSequence.beginPage())
    }

    func testMangaPaginationRestrictsContinuationToItsMALList() throws {
        var sequence = TrackerRemoteProgressBoundary.PageSequence()
        let invalidURLs = [
            "http://api.myanimelist.net/v2/users/@me/mangalist?offset=1000",
            "https://example.com/v2/users/@me/mangalist?offset=1000",
            "https://api.myanimelist.net:443/v2/users/@me/mangalist?offset=1000",
            "https://api.myanimelist.net/v2/users/@me/animelist?offset=1000",
            "https://api.myanimelist.net/v2/manga/1"
        ]
        for raw in invalidURLs {
            let url = try XCTUnwrap(URL(string: raw))
            XCTAssertFalse(sequence.beginMALPage(url, listKind: .manga))
        }
        let mangaURL = try XCTUnwrap(URL(string: "https://api.myanimelist.net/v2/users/@me/mangalist?offset=0"))
        let animeURL = try XCTUnwrap(URL(string: "https://api.myanimelist.net/v2/users/@me/animelist?offset=0"))
        XCTAssertTrue(sequence.beginMALPage(mangaURL, listKind: .manga))
        XCTAssertTrue(TrackerRemoteProgressBoundary.isAllowedMALPageURL(animeURL))
        XCTAssertFalse(TrackerRemoteProgressBoundary.isAllowedMALPageURL(mangaURL))
    }

    func testMangaPaginationRejectsOversizedAggregateBeforeAppending() {
        XCTAssertTrue(TrackerRemoteProgressBoundary.canAppendEntries(500, existingCount: 99_500))
        XCTAssertTrue(TrackerRemoteProgressBoundary.canAppendEntries(0, existingCount: 100_000))
        XCTAssertFalse(TrackerRemoteProgressBoundary.canAppendEntries(1, existingCount: 100_000))
        XCTAssertFalse(TrackerRemoteProgressBoundary.canAppendEntries(100_001, existingCount: 0))
        XCTAssertFalse(TrackerRemoteProgressBoundary.canAppendEntries(Int.max, existingCount: 1))
        XCTAssertFalse(TrackerRemoteProgressBoundary.canAppendEntries(1, existingCount: Int.max))
        XCTAssertFalse(TrackerRemoteProgressBoundary.canAppendEntries(-1, existingCount: 0))
        XCTAssertFalse(TrackerRemoteProgressBoundary.canAppendEntries(0, existingCount: -1))
    }

    func testImportedPagePositionsClampBeforeConvertingToDisplayedPage() throws {
        let data = try JSONSerialization.data(withJSONObject: [
            "pagePositions": ["1": Int.max, "2": Int.min],
            "pageCounts": ["1": 5, "2": Int.max]
        ])
        let progress = try JSONDecoder().decode(MangaProgress.self, from: data)
        let first = try XCTUnwrap(progress.pagePositions["1"])
        let second = try XCTUnwrap(progress.pagePositions["2"])
        XCTAssertEqual(MangaProgress.displayedPage(position: first, total: 5), 5)
        XCTAssertEqual(MangaProgress.displayedPage(position: second, total: Int.max), 1)
        XCTAssertEqual(MangaProgress.displayedPage(position: Int.max, total: Int.max), Int.max)
        XCTAssertEqual(MangaProgress.displayedPage(position: 3, total: 5), 4)
        XCTAssertNil(MangaProgress.displayedPage(position: 0, total: 0))
        XCTAssertNil(MangaProgress.displayedPage(position: 0, total: Int.min))
    }
}

#endif
