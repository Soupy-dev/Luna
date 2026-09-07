import XCTest
@testable import Eclipse

final class PlaybackInputSafetyTests: XCTestCase {
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
