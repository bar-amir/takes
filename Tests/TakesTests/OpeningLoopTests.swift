import AVFoundation
import XCTest
@testable import Takes

/// The opening screen plays a loop of its photo. The loop has to ship next to the photo, be silent, match the photo's
/// shape so it lines up when scaled to fill, and be short enough to read as a loop.
final class OpeningLoopTests: XCTestCase {
    func testTheLoopShipsWithThePhoto() throws {
        XCTAssertNotNil(BrandResources.openingImage)
        XCTAssertNotNil(BrandResources.openingLoop, "Resources/Onboarding/opening-loop.mp4 is missing")
    }

    func testTheLoopIsSilentAndMatchesThePhoto() async throws {
        let url = try XCTUnwrap(BrandResources.openingLoop)
        let image = try XCTUnwrap(BrandResources.openingImage)
        let asset = AVURLAsset(url: url)
        let audio = try await asset.loadTracks(withMediaType: .audio)
        XCTAssertTrue(audio.isEmpty, "The loop plays muted; it shouldn't carry an audio track")
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        let video = try XCTUnwrap(videoTracks.first)
        let size = try await video.load(.naturalSize)
        XCTAssertEqual(size.width / size.height, image.size.width / image.size.height, accuracy: 0.01)
        let seconds = try await asset.load(.duration).seconds
        XCTAssertGreaterThan(seconds, 2)
        XCTAssertLessThan(seconds, 10)
    }
}
