//
//  SpeechNowPlaying.swift
//  Angrove-iOS
//

import MediaPlayer
import UIKit

/// Shows the response being read on the Lock Screen and in Control Center, with play/pause,
/// skip, and a scrubber wired back to `ResponseSpeechPlayer`.
@MainActor
final class SpeechNowPlaying {
    static let shared = SpeechNowPlaying()

    static let skipInterval: Double = 15

    private var isActive = false
    private var areCommandsRegistered = false
    private lazy var artwork: MPMediaItemArtwork? = UIImage(named: AppIconImage.assetName).map { image in
        MPMediaItemArtwork(boundsSize: image.size) { _ in image }
    }

    func update(title: String, elapsed: Double, duration: Double, isPlaying: Bool) {
        registerCommandsIfNeeded()
        UIApplication.shared.beginReceivingRemoteControlEvents()
        isActive = true
        setCommandsEnabled(true)
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: title,
            MPMediaItemPropertyArtist: "Angrove",
            MPMediaItemPropertyPlaybackDuration: max(duration, elapsed),
            MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsed,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
        ]
        if let artwork { info[MPMediaItemPropertyArtwork] = artwork }
        let center = MPNowPlayingInfoCenter.default()
        center.nowPlayingInfo = info
        center.playbackState = isPlaying ? .playing : .paused
    }

    func clear() {
        guard isActive else { return }
        isActive = false
        setCommandsEnabled(false)
        let center = MPNowPlayingInfoCenter.default()
        center.nowPlayingInfo = nil
        center.playbackState = .stopped
    }

    private func setCommandsEnabled(_ isEnabled: Bool) {
        let commands = MPRemoteCommandCenter.shared()
        for command in [
            commands.playCommand, commands.pauseCommand, commands.togglePlayPauseCommand,
            commands.skipForwardCommand, commands.skipBackwardCommand, commands.changePlaybackPositionCommand,
        ] {
            command.isEnabled = isEnabled
        }
    }

    private func registerCommandsIfNeeded() {
        guard !areCommandsRegistered else { return }
        areCommandsRegistered = true
        let commands = MPRemoteCommandCenter.shared()
        let player = ResponseSpeechPlayer.shared

        commands.playCommand.addTarget { _ in
            Task { @MainActor in player.resume() }
            return .success
        }
        commands.pauseCommand.addTarget { _ in
            Task { @MainActor in player.pause() }
            return .success
        }
        commands.togglePlayPauseCommand.addTarget { _ in
            Task { @MainActor in player.isPaused ? player.resume() : player.pause() }
            return .success
        }
        commands.skipForwardCommand.preferredIntervals = [NSNumber(value: Self.skipInterval)]
        commands.skipForwardCommand.addTarget { _ in
            Task { @MainActor in player.skip(by: Self.skipInterval) }
            return .success
        }
        commands.skipBackwardCommand.preferredIntervals = [NSNumber(value: Self.skipInterval)]
        commands.skipBackwardCommand.addTarget { _ in
            Task { @MainActor in player.skip(by: -Self.skipInterval) }
            return .success
        }
        commands.changePlaybackPositionCommand.addTarget { event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            let position = event.positionTime
            Task { @MainActor in player.seek(toTime: position) }
            return .success
        }
        for command in [commands.nextTrackCommand, commands.previousTrackCommand,
                        commands.seekForwardCommand, commands.seekBackwardCommand] {
            command.isEnabled = false
        }
    }
}
