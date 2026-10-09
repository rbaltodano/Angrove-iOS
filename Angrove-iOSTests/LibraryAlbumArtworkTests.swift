import MediaPlayer
import Testing
import UIKit
@testable import Angrove_iOS

@Suite("Library album artwork")
@MainActor
struct LibraryAlbumArtworkTests {
    @Test("Each genre supplies its full-size cover, including Aquinas after the merge")
    func genreCovers() throws {
        let examples = [
            ("web-bible", "LibraryAlbumScripture"),
            ("summa-theologica", "LibraryAlbumChurchHistory"),
            ("augustine-confessions", "LibraryAlbumChurchHistory"),
            ("council-of-trent", "LibraryAlbumCouncilsCreeds"),
            ("baltimore-catechism-3", "LibraryAlbumConfessions"),
            ("aristotle-nicomachean-ethics", "LibraryAlbumPhilosophy"),
            ("herodotus-histories", "LibraryAlbumWorldHistory"),
            ("adam-smith-wealth-of-nations", "LibraryAlbumPoliticalThought"),
        ]
        let nowPlaying = SpeechNowPlaying()
        for (workID, assetName) in examples {
            #expect(LibraryAlbumArtwork.assetName(forLibraryWorkID: workID) == assetName)
            let original = try #require(UIImage(named: assetName))
            #expect(original.size == CGSize(width: 1024, height: 1024))
            let artwork = try #require(nowPlaying.artwork(forLibraryWorkID: workID))
            let delivered = try #require(artwork.image(at: CGSize(width: 1024, height: 1024)))
            #expect(delivered.pngData() == original.pngData())
        }
    }

    @Test("Switching genres updates artwork; conversations keep the Angrove logo")
    func switchingReadings() throws {
        let nowPlaying = SpeechNowPlaying()
        let scripture = try #require(nowPlaying.artwork(forLibraryWorkID: "web-bible"))
        let philosophy = try #require(nowPlaying.artwork(forLibraryWorkID: "aristotle-nicomachean-ethics"))
        #expect(scripture !== philosophy)
        #expect(nowPlaying.artwork(forLibraryWorkID: "web-bible") === scripture)
        #expect(LibraryAlbumArtwork.assetName(forLibraryWorkID: nil) == AppIconImage.assetName)
        let conversation = try #require(nowPlaying.artwork(forLibraryWorkID: nil))
        let logo = try #require(UIImage(named: AppIconImage.assetName))
        #expect(conversation.image(at: logo.size)?.pngData() == logo.pngData())
    }
}
