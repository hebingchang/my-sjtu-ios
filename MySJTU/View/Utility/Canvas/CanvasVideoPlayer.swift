//
//  CanvasVideoPlayer.swift
//  MySJTU
//
//  Created by boar on 2026/03/29.
//

import SwiftUI
import AVFoundation
import MediaPlayer
import UIKit
@preconcurrency import VLCKitSPM

struct CanvasVideoFullscreenPlayerView: View {
    let title: String
    let subtitle: String?
    let streams: [CanvasVideoPlayableStream]
    let subtitles: [CanvasVideoTranscriptSegment]
    let durationHintSeconds: Int?
    private let isLiveMode: Bool
    private let scrubPreviewContext: CanvasVideoScrubPreviewContext?

    @Environment(\.dismiss) private var dismiss
    @StateObject private var playback: CanvasVideoPlaybackCoordinator
    @State private var scrubPosition: Double = 0
    @State private var isScrubbing: Bool = false
    @State private var scrubRangeUpperBound: Double?
    @State private var chromeVisible: Bool = true
    @State private var chromeHideTask: Task<Void, Never>?
    @State private var scrubCompletionTask: Task<Void, Never>?
    @State private var subtitlesEnabled: Bool = true
    @State private var preferredLandscapeLayout: CanvasVideoLandscapeLayout = .sideBySide
    @State private var preferredMajorStreamID: Int?
    @State private var preferredMinorStreamID: Int?
    @State private var floatingMinorOffset: CGSize = .zero
    @State private var floatingMinorDragStartOffset: CGSize?
    @State private var subtitleOffset: CGSize = .zero
    @State private var subtitleDragStartOffset: CGSize?
    @State private var subtitleOverlaySize: CGSize = .zero
    private let subtitleHorizontalInset: CGFloat = 18
    private let subtitleBoundaryInset: CGFloat = 18
    private let subtitleScreenBottomInset: CGFloat = 124
    private let headerBadgeReservedWidth: CGFloat = 120
    private let floatingMinorMargin: CGFloat = 18
    private let majorVideoSwapAnimation = Animation.easeInOut(duration: 0.24)
    private let landscapeLayoutTransitionAnimation = Animation.spring(response: 0.34, dampingFraction: 0.86)

    init(
        title: String,
        subtitle: String?,
        streams: [CanvasVideoPlayableStream],
        subtitles: [CanvasVideoTranscriptSegment],
        durationHintSeconds: Int?,
        session: CanvasVideoPlatformSession,
        previewCourseID: Int? = nil
    ) {
        let resolvedLiveMode = durationHintSeconds == nil && streams.contains(where: { $0.format == .flv })

        self.title = title
        self.subtitle = subtitle
        self.streams = streams
        self.subtitles = subtitles
        self.durationHintSeconds = durationHintSeconds
        self.isLiveMode = resolvedLiveMode
        self.scrubPreviewContext = resolvedLiveMode
            ? nil
            : previewCourseID.map {
                CanvasVideoScrubPreviewContext(
                    session: session,
                    courseId: $0
                )
            }
        _playback = StateObject(
            wrappedValue: CanvasVideoPlaybackCoordinator(
                title: title,
                subtitle: subtitle,
                streams: streams,
                subtitles: subtitles,
                durationHintSeconds: durationHintSeconds,
                isLiveMode: resolvedLiveMode
            )
        )
    }

    private var progressBinding: Binding<Double> {
        Binding(
            get: {
                isScrubbing ? scrubPosition : playback.currentTime
            },
            set: { newValue in
                scrubPosition = newValue
                if !isScrubbing {
                    beginScrubbingIfNeeded()
                }
            }
        )
    }

    private var progressRange: ClosedRange<Double> {
        let upperBound = max(scrubRangeUpperBound ?? liveProgressUpperBound, 1)
        return 0...upperBound
    }

    private var liveProgressUpperBound: Double {
        max(playback.duration, playback.currentTime, 1)
    }

    private var featuredStreamPlayers: [CanvasVideoStreamPlayer] {
        Array(playback.streamPlayers.prefix(min(playback.streamPlayers.count, 2)))
    }

    private var additionalStreamPlayers: [CanvasVideoStreamPlayer] {
        Array(playback.streamPlayers.dropFirst(min(playback.streamPlayers.count, 2)))
    }

    private var canUseFloatingLayout: Bool {
        playback.streamPlayers.count > 1
    }

    private var usesVLCBackedPlayback: Bool {
        playback.streamPlayers.contains { $0.vlcPlayer != nil }
    }

    private var activeLandscapeLayout: CanvasVideoLandscapeLayout {
        canUseFloatingLayout ? preferredLandscapeLayout : .sideBySide
    }

    private var selectedMajorStreamPlayer: CanvasVideoStreamPlayer? {
        if let preferredMajorStreamID,
           let matchedPlayer = playback.streamPlayers.first(where: { $0.id == preferredMajorStreamID }) {
            return matchedPlayer
        }

        return playback.streamPlayers.first
    }

    private var selectedMinorCandidates: [CanvasVideoStreamPlayer] {
        guard let selectedMajorStreamPlayer else {
            return []
        }

        return playback.streamPlayers.filter { $0.id != selectedMajorStreamPlayer.id }
    }

    private var selectedMinorStreamPlayer: CanvasVideoStreamPlayer? {
        if let preferredMinorStreamID,
           let matchedPlayer = selectedMinorCandidates.first(where: { $0.id == preferredMinorStreamID }) {
            return matchedPlayer
        }

        return selectedMinorCandidates.first
    }

    private var usesFloatingLandscapeLayout: Bool {
        activeLandscapeLayout == .floatingOverlay
            && selectedMajorStreamPlayer != nil
            && selectedMinorStreamPlayer != nil
    }

    private var stableLandscapeMajorStreamPlayer: CanvasVideoStreamPlayer? {
        selectedMajorStreamPlayer ?? playback.streamPlayers.first
    }

    private var stableLandscapeMinorStreamPlayer: CanvasVideoStreamPlayer? {
        selectedMinorStreamPlayer
            ?? playback.streamPlayers.dropFirst().first
    }

    private var stableVLCStagePlayers: [CanvasVideoStreamPlayer] {
        var players: [CanvasVideoStreamPlayer] = []

        if let majorStreamPlayer = stableLandscapeMajorStreamPlayer {
            players.append(majorStreamPlayer)
        }

        if let minorStreamPlayer = stableLandscapeMinorStreamPlayer,
           players.contains(where: { $0.id == minorStreamPlayer.id }) == false {
            players.append(minorStreamPlayer)
        }

        return players
    }

    private var stableVLCAdditionalStreamPlayers: [CanvasVideoStreamPlayer] {
        let excludedIDs = Set(stableVLCStagePlayers.map(\.id))
        return playback.streamPlayers.filter { excludedIDs.contains($0.id) == false }
    }

    private var headerOpacity: Double {
        (chromeVisible || playback.primaryStreamPlayer == nil) ? 1 : 0
    }

    private var controlsOpacity: Double {
        (chromeVisible && playback.primaryStreamPlayer != nil) ? 1 : 0
    }

    private var badgeOpacity: Double {
        chromeVisible ? 1 : 0
    }

    private var landscapeLayoutTransition: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.97)),
            removal: .opacity.combined(with: .scale(scale: 1.02))
        )
    }

    var body: some View {
        GeometryReader { geometry in
            let isLandscape = geometry.size.width > geometry.size.height

            ZStack {
                Color.black.ignoresSafeArea()

                if playback.primaryStreamPlayer == nil {
                    unavailableState
                        .padding(.horizontal, 20)
                } else {
                    Group {
                        if usesVLCBackedPlayback {
                            stableVLCStage(isLandscape: isLandscape)
                        } else if isLandscape {
                            animatedLandscapeStage
                        } else {
                            portraitStage
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

            }
            .contentShape(Rectangle())
            .onTapGesture {
                handleStageTap()
            }
            .overlay(alignment: .top) {
                header(
                    isLandscape: isLandscape
                )
                    .opacity(headerOpacity)
                    .animation(.easeInOut(duration: 0.22), value: chromeVisible)
                    .allowsHitTesting(chromeVisible || playback.primaryStreamPlayer == nil)
            }
            .overlay(alignment: .topTrailing) {
                bufferingBadge
                    .padding(.top, 24)
                    .padding(.trailing, 20)
                    .allowsHitTesting(false)
                    .animation(.easeInOut(duration: 0.22), value: playback.isBuffering)
            }
            .overlay(alignment: .bottom) {
                subtitleOverlay(
                    containerSize: geometry.size,
                    safeAreaTop: geometry.safeAreaInsets.top,
                    safeAreaBottom: geometry.safeAreaInsets.bottom
                )
            }
            .overlay(alignment: .bottom) {
                controlsOverlay(isLandscape: isLandscape)
                    .opacity(controlsOpacity)
                    .animation(.easeInOut(duration: 0.22), value: chromeVisible)
                    .allowsHitTesting(chromeVisible && playback.primaryStreamPlayer != nil)
            }
            .onChange(of: geometry.size) { _, newSize in
                subtitleOffset = clampedSubtitleOffset(
                    proposed: subtitleOffset,
                    containerSize: newSize,
                    safeAreaTop: geometry.safeAreaInsets.top,
                    safeAreaBottom: geometry.safeAreaInsets.bottom
                )
            }
            .onChange(of: subtitleOverlaySize) { _, newSize in
                guard newSize != .zero else {
                    return
                }

                subtitleOffset = clampedSubtitleOffset(
                    proposed: subtitleOffset,
                    containerSize: geometry.size,
                    safeAreaTop: geometry.safeAreaInsets.top,
                    safeAreaBottom: geometry.safeAreaInsets.bottom
                )
            }
        }
        .statusBar(hidden: true)
        .onAppear {
            ensureFloatingSelections()
            CanvasVideoOrientationController.enableVideoPlayerOrientations()
            scrubPosition = playback.currentTime
            playback.startPlayback()
            showChromeAndScheduleHide()
        }
        .onDisappear {
            chromeHideTask?.cancel()
            scrubCompletionTask?.cancel()
            playback.stopPlayback(prepareForResume: false)
            CanvasVideoOrientationController.restoreDefaultOrientations()
        }
        .onChange(of: playback.currentTime) { _, newValue in
            if !isScrubbing {
                scrubPosition = newValue
            }
        }
        .onChange(of: subtitles) { _, newValue in
            playback.updateSubtitles(newValue)
        }
        .onChange(of: durationHintSeconds) { _, newValue in
            playback.updateDurationHint(seconds: newValue)
        }
    }

    private func header(isLandscape: Bool) -> some View {
        Group {
            if isLandscape {
                HStack(alignment: .top, spacing: 12) {
                    closeButton

                    titleBlock
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, headerBadgeReservedWidth)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    closeButton

                    titleBlock
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, headerBadgeReservedWidth)
            }
        }
        .padding(.top, isLandscape ? 24 : 12)
        .padding(.horizontal, 20)
        .padding(.bottom, 28)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            LinearGradient(
                colors: [
                    Color.black.opacity(0.9),
                    Color.black.opacity(0.45),
                    .clear
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(maxWidth: .infinity)
            .frame(height: 160)
            .ignoresSafeArea(edges: .top)
            .allowsHitTesting(false)
        }
    }

    private var closeButton: some View {
        Button(action: closePlayer) {
            Image(systemName: "xmark.circle.fill")
                .font(.title2)
                .foregroundStyle(.white.opacity(0.92))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.leading)

            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.74))
                    .multilineTextAlignment(.leading)
            }
        }
    }

    @ViewBuilder
    private var bufferingBadge: some View {
        if playback.isBuffering {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                    .tint(.white)

                Text("正在缓冲")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.84))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.08), in: Capsule())
        }
    }

    private var portraitStage: some View {
        VStack(spacing: 12) {
            if let firstStreamPlayer = featuredStreamPlayers.first {
                stageCard(
                    for: firstStreamPlayer,
                    cornerRadius: 24
                )
            }

            if featuredStreamPlayers.count > 1 {
                stageCard(
                    for: featuredStreamPlayers[1],
                    cornerRadius: 24
                )
            }

            if !additionalStreamPlayers.isEmpty {
                additionalStageStrip
            }
        }
    }

    @ViewBuilder
    private func stableResponsiveStage(isLandscape: Bool) -> some View {
        VStack(spacing: 12) {
            if featuredStreamPlayers.count > 1 {
                let layout = isLandscape
                    ? AnyLayout(HStackLayout(spacing: 12))
                    : AnyLayout(VStackLayout(spacing: 12))

                layout {
                    ForEach(Array(featuredStreamPlayers.prefix(2))) { streamPlayer in
                        stageCard(
                            for: streamPlayer,
                            cornerRadius: 24
                        )
                    }
                }
            } else if let firstStreamPlayer = featuredStreamPlayers.first {
                stageCard(
                    for: firstStreamPlayer,
                    cornerRadius: 24
                )
            }

            if !additionalStreamPlayers.isEmpty {
                additionalStageStrip
            }
        }
    }

    private var landscapeStage: some View {
        VStack(spacing: 12) {
            if featuredStreamPlayers.count > 1 {
                HStack(spacing: 12) {
                    stageCard(
                        for: featuredStreamPlayers[0],
                        cornerRadius: 24
                    )

                    stageCard(
                        for: featuredStreamPlayers[1],
                        cornerRadius: 24
                    )
                }
            } else if let firstStreamPlayer = featuredStreamPlayers.first {
                stageCard(
                    for: firstStreamPlayer,
                    cornerRadius: 24
                )
            }

            if !additionalStreamPlayers.isEmpty {
                additionalStageStrip
            }
        }
    }

    private var animatedLandscapeStage: some View {
        ZStack {
            if usesFloatingLandscapeLayout {
                floatingLandscapeStage
                    .transition(landscapeLayoutTransition)
            } else {
                landscapeStage
                    .transition(landscapeLayoutTransition)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(landscapeLayoutTransitionAnimation, value: usesFloatingLandscapeLayout)
    }

    private var floatingLandscapeStage: some View {
        GeometryReader { stageGeometry in
            let majorSize = fittedAspectSize(
                aspectRatio: 16 / 9,
                in: stageGeometry.size
            )
            let minorSize = floatingMinorCardSize(in: majorSize)

            ZStack {
                if let selectedMajorStreamPlayer {
                    stageCard(
                        for: selectedMajorStreamPlayer,
                        cornerRadius: 24
                    )
                    .id(selectedMajorStreamPlayer.id)
                    .frame(width: majorSize.width, height: majorSize.height)
                    .transition(
                        .asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.985)),
                            removal: .opacity
                        )
                    )
                }

                if let selectedMinorStreamPlayer {
                    stageCard(
                        for: selectedMinorStreamPlayer,
                        cornerRadius: 20
                    )
                    .frame(width: minorSize.width, height: minorSize.height)
                    .transition(
                        .asymmetric(
                            insertion: .opacity
                                .combined(with: .scale(scale: 0.92))
                                .combined(with: .offset(x: 24, y: 18)),
                            removal: .opacity.combined(with: .scale(scale: 0.96))
                        )
                    )
                    .offset(
                        floatingMinorDisplayOffset(
                            majorSize: majorSize,
                            minorSize: minorSize
                        )
                    )
                    .gesture(
                        floatingMinorGesture(
                            majorSize: majorSize,
                            minorSize: minorSize
                        )
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(majorVideoSwapAnimation, value: selectedMajorStreamPlayer?.id)
        }
    }

    private var additionalStageStrip: some View {
        additionalStageStrip(for: additionalStreamPlayers)
    }

    private func additionalStageStrip(
        for streamPlayers: [CanvasVideoStreamPlayer]
    ) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(streamPlayers) { streamPlayer in
                    stageCard(for: streamPlayer, cornerRadius: 18)
                        .frame(width: 220)
                }
            }
            .padding(.horizontal, 2)
        }
        .frame(height: 136)
    }

    @ViewBuilder
    private func stableVLCStage(isLandscape: Bool) -> some View {
        VStack(spacing: 12) {
            if stableVLCStagePlayers.count > 1 {
                GeometryReader { stageGeometry in
                    let splitCardSize = isLandscape
                        ? splitLandscapeCardSize(in: stageGeometry.size)
                        : splitPortraitCardSize(in: stageGeometry.size)
                    let showsFloatingMinorOverlay = isLandscape && usesFloatingLandscapeLayout
                    let majorSize = showsFloatingMinorOverlay
                        ? fittedAspectSize(aspectRatio: 16 / 9, in: stageGeometry.size)
                        : splitCardSize
                    let minorSize = showsFloatingMinorOverlay
                        ? floatingMinorCardSize(in: majorSize)
                        : splitCardSize

                    ZStack {
                        ForEach(Array(stableVLCStagePlayers.enumerated()), id: \.element.id) { index, streamPlayer in
                            let isMajorStream = index == 0
                            let cardSize = isMajorStream ? majorSize : minorSize

                            stageCard(
                                for: streamPlayer,
                                cornerRadius: (showsFloatingMinorOverlay && !isMajorStream) ? 20 : 24
                            )
                            .frame(width: cardSize.width, height: cardSize.height)
                            .offset(
                                showsFloatingMinorOverlay
                                    ? (
                                        isMajorStream
                                            ? .zero
                                            : floatingMinorDisplayOffset(
                                                majorSize: majorSize,
                                                minorSize: minorSize
                                            )
                                    )
                                    : splitStageCardOffset(
                                        size: splitCardSize,
                                        isLandscape: isLandscape,
                                        direction: isMajorStream ? -1 : 1
                                    )
                            )
                            .gesture(
                                floatingMinorGesture(
                                    majorSize: majorSize,
                                    minorSize: minorSize
                                ),
                                including: (showsFloatingMinorOverlay && !isMajorStream) ? .all : .none
                            )
                            .zIndex(isMajorStream ? 0 : 1)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else if let firstStreamPlayer = stableVLCStagePlayers.first {
                stageCard(
                    for: firstStreamPlayer,
                    cornerRadius: 24
                )
            }

            if !stableVLCAdditionalStreamPlayers.isEmpty {
                additionalStageStrip(for: stableVLCAdditionalStreamPlayers)
            }
        }
    }

    private func stageCard(
        for streamPlayer: CanvasVideoStreamPlayer,
        cornerRadius: CGFloat
    ) -> some View {
        ZStack(alignment: .bottomLeading) {
            CanvasVideoPlayerSurface(streamPlayer: streamPlayer)
        }
        .aspectRatio(16 / 9, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(alignment: .topLeading) {
            streamBadge(title: streamPlayer.stream.title)
                .padding(12)
                .opacity(badgeOpacity)
                .animation(.easeInOut(duration: 0.22), value: chromeVisible)
                .allowsHitTesting(false)
        }
        .background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
    }

    private func subtitleOverlay(
        containerSize: CGSize,
        safeAreaTop: CGFloat,
        safeAreaBottom: CGFloat
    ) -> some View {
        Group {
            if subtitlesEnabled, let activeSubtitleText = playback.activeSubtitleText {
                Text(activeSubtitleText)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(Color.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .padding(.horizontal, subtitleHorizontalInset)
                    .background {
                        GeometryReader { geometry in
                            Color.clear
                                .preference(
                                    key: CanvasVideoSubtitleOverlaySizePreferenceKey.self,
                                    value: geometry.size
                                )
                        }
                    }
                    .onPreferenceChange(CanvasVideoSubtitleOverlaySizePreferenceKey.self) { newSize in
                        if subtitleOverlaySize != newSize {
                            subtitleOverlaySize = newSize
                        }
                    }
                    .contentShape(Rectangle())
                    .offset(
                        clampedSubtitleOffset(
                            proposed: subtitleOffset,
                            containerSize: containerSize,
                            safeAreaTop: safeAreaTop,
                            safeAreaBottom: safeAreaBottom
                        )
                    )
                    .padding(.bottom, safeAreaBottom + subtitleScreenBottomInset)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .gesture(
                        subtitleDragGesture(
                            containerSize: containerSize,
                            safeAreaTop: safeAreaTop,
                            safeAreaBottom: safeAreaBottom
                        )
                    )
            }
        }
    }

    private func subtitleDragGesture(
        containerSize: CGSize,
        safeAreaTop: CGFloat,
        safeAreaBottom: CGFloat
    ) -> some Gesture {
        DragGesture()
            .onChanged { value in
                if subtitleDragStartOffset == nil {
                    subtitleDragStartOffset = subtitleOffset
                }

                let baseOffset = subtitleDragStartOffset ?? subtitleOffset
                subtitleOffset = clampedSubtitleOffset(
                    proposed: CGSize(
                        width: baseOffset.width + value.translation.width,
                        height: baseOffset.height + value.translation.height
                    ),
                    containerSize: containerSize,
                    safeAreaTop: safeAreaTop,
                    safeAreaBottom: safeAreaBottom
                )
            }
            .onEnded { value in
                let baseOffset = subtitleDragStartOffset ?? subtitleOffset
                subtitleOffset = clampedSubtitleOffset(
                    proposed: CGSize(
                        width: baseOffset.width + value.translation.width,
                        height: baseOffset.height + value.translation.height
                    ),
                    containerSize: containerSize,
                    safeAreaTop: safeAreaTop,
                    safeAreaBottom: safeAreaBottom
                )
                subtitleDragStartOffset = nil
            }
    }

    private func clampedSubtitleOffset(
        proposed: CGSize,
        containerSize: CGSize,
        safeAreaTop: CGFloat,
        safeAreaBottom: CGFloat
    ) -> CGSize {
        let overlayWidth = subtitleOverlaySize.width
        let overlayHeight = subtitleOverlaySize.height

        let horizontalLimit = max((containerSize.width - overlayWidth) / 2, 0)
        let clampedX = clamp(
            proposed.width,
            minValue: -horizontalLimit,
            maxValue: horizontalLimit
        )

        let defaultCenterY = (containerSize.height / 2)
            - (safeAreaBottom + subtitleScreenBottomInset)
            - (overlayHeight / 2)
        let minCenterY = (-containerSize.height / 2)
            + safeAreaTop
            + subtitleBoundaryInset
            + (overlayHeight / 2)
        let maxCenterY = (containerSize.height / 2)
            - safeAreaBottom
            - subtitleBoundaryInset
            - (overlayHeight / 2)

        let minOffsetY = minCenterY - defaultCenterY
        let maxOffsetY = maxCenterY - defaultCenterY
        let clampedY: CGFloat
        if minOffsetY <= maxOffsetY {
            clampedY = clamp(
                proposed.height,
                minValue: minOffsetY,
                maxValue: maxOffsetY
            )
        } else {
            clampedY = 0
        }

        return CGSize(width: clampedX, height: clampedY)
    }

    private func clamp(
        _ value: CGFloat,
        minValue: CGFloat,
        maxValue: CGFloat
    ) -> CGFloat {
        min(max(value, minValue), maxValue)
    }

    private func controlsOverlay(isLandscape: Bool) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if !isLiveMode {
                timelineSection(isLandscape: isLandscape)
            }

            ZStack {
                if !isLiveMode {
                    HStack(spacing: 28) {
                        Button(action: {
                            performPlaybackAction {
                                playback.skip(by: -15)
                            }
                        }) {
                            Image(systemName: "gobackward.15")
                                .font(.title2.weight(.medium))
                                .foregroundStyle(.white)
                        }
                        .buttonStyle(.plain)

                        Button(action: {
                            performPlaybackAction {
                                playback.togglePlayback()
                            }
                        }) {
                            Image(systemName: playback.showsPauseButton ? "pause.circle.fill" : "play.circle.fill")
                                .font(.system(size: 54))
                                .foregroundStyle(.white)
                        }
                        .buttonStyle(.plain)

                        Button(action: {
                            performPlaybackAction {
                                playback.skip(by: 15)
                            }
                        }) {
                            Image(systemName: "goforward.15")
                                .font(.title2.weight(.medium))
                                .foregroundStyle(.white)
                        }
                        .buttonStyle(.plain)
                    }
                    .frame(maxWidth: .infinity)
                }

                HStack(spacing: 12) {
                    Spacer()

                    CanvasVideoControlMenus(
                        isLandscape: isLandscape,
                        showsSubtitleSettings: !isLiveMode,
                        subtitlesEnabled: subtitlesEnabled,
                        subtitleOffsetIsZero: subtitleOffset == .zero,
                        preferredLandscapeLayout: preferredLandscapeLayout,
                        canUseFloatingLayout: canUseFloatingLayout,
                        showsFloatingCustomization: isLandscape && activeLandscapeLayout == .floatingOverlay,
                        streamOptions: playback.streamPlayers.map {
                            CanvasVideoMenuStreamOption(id: $0.id, title: $0.stream.title)
                        },
                        selectedMajorStreamID: selectedMajorStreamPlayer?.id,
                        minorStreamOptions: selectedMinorCandidates.map {
                            CanvasVideoMenuStreamOption(id: $0.id, title: $0.stream.title)
                        },
                        selectedMinorStreamID: selectedMinorStreamPlayer?.id,
                        onSubtitleEnabledChange: { newValue in
                            subtitlesEnabled = newValue
                            showChromeAndScheduleHide()
                        },
                        onResetSubtitle: {
                            subtitleOffset = .zero
                            showChromeAndScheduleHide()
                        },
                        onSetLandscapeLayout: { layout in
                            setLandscapeLayout(layout)
                        },
                        onSelectMajorStream: { streamID in
                            selectMajorStream(streamID)
                        },
                        onSelectMinorStream: { streamID in
                            selectMinorStream(streamID)
                        }
                    )
                    .equatable()
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 28)
        .padding(.bottom, 0)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(alignment: .bottom) {
            LinearGradient(
                colors: [
                    .clear,
                    Color.black.opacity(0.45),
                    Color.black.opacity(0.9)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(maxWidth: .infinity)
            .frame(height: 210)
            .ignoresSafeArea(edges: .bottom)
            .allowsHitTesting(false)
        }
    }

    private func timelineSection(isLandscape: Bool) -> some View {
        let currentTimeText = formatPlaybackSeconds(isScrubbing ? scrubPosition : playback.currentTime)
        let durationText = formatPlaybackSeconds(playback.duration)

        return Group {
            if isLandscape {
                HStack(spacing: 12) {
                    timelineLabel(currentTimeText)

                    CanvasVideoScrubber(
                        value: progressBinding,
                        range: progressRange,
                        previewContext: scrubPreviewContext,
                        onEditingChanged: handleScrubbingChanged
                    )

                    timelineLabel(durationText)
                }
            } else {
                CanvasVideoScrubber(
                    value: progressBinding,
                    range: progressRange,
                    previewContext: scrubPreviewContext,
                    onEditingChanged: handleScrubbingChanged
                )

                HStack {
                    timelineLabel(currentTimeText)

                    Spacer()

                    timelineLabel(durationText)
                }
            }
        }
    }

    private func timelineLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption.monospacedDigit())
            .foregroundStyle(.white.opacity(0.82))
    }

    private var unavailableState: some View {
        VStack(spacing: 14) {
            Spacer()

            Image(systemName: "play.slash")
                .font(.system(size: 42, weight: .medium))
                .foregroundStyle(.white.opacity(0.78))

            Text("暂无可播放的视频流")
                .font(.headline)
                .foregroundStyle(.white)

            Text("视频平台暂时没有返回可用的播放地址。")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.72))

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func streamBadge(title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.black.opacity(0.64), in: Capsule())
    }

    private func handleScrubbingChanged(_ isEditing: Bool) {
        if isEditing {
            beginScrubbingIfNeeded()
        } else {
            let targetPosition = scrubPosition
            scrubCompletionTask?.cancel()
            scrubCompletionTask = Task {
                await playback.completeScrubbing(at: targetPosition)
                guard !Task.isCancelled else {
                    return
                }

                await MainActor.run {
                    scrubRangeUpperBound = nil
                    isScrubbing = false
                    scrubCompletionTask = nil
                    showChromeAndScheduleHide()
                }
            }
        }
    }

    private func beginScrubbingIfNeeded() {
        guard !isLiveMode, !isScrubbing else {
            return
        }

        scrubCompletionTask?.cancel()
        scrubRangeUpperBound = liveProgressUpperBound
        isScrubbing = true
        showChrome()
        playback.beginScrubbing()
    }

    private func handleStageTap() {
        guard playback.primaryStreamPlayer != nil else {
            return
        }

        if chromeVisible {
            hideChrome()
        } else {
            showChromeAndScheduleHide()
        }
    }

    private func performPlaybackAction(_ action: () -> Void) {
        action()
        showChromeAndScheduleHide()
    }

    private func showChrome() {
        chromeHideTask?.cancel()
        chromeVisible = true
    }

    private func showChromeAndScheduleHide() {
        showChrome()
        guard playback.primaryStreamPlayer != nil else {
            return
        }

        chromeHideTask = Task {
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            guard !Task.isCancelled else {
                return
            }

            await MainActor.run {
                if !isScrubbing {
                    chromeVisible = false
                }
            }
        }
    }

    private func hideChrome() {
        chromeHideTask?.cancel()
        chromeVisible = false
    }

    private func ensureFloatingSelections() {
        guard canUseFloatingLayout else {
            preferredMajorStreamID = playback.streamPlayers.first?.id
            preferredMinorStreamID = nil
            return
        }

        if preferredMajorStreamID == nil
            || playback.streamPlayers.contains(where: { $0.id == preferredMajorStreamID }) == false {
            preferredMajorStreamID = playback.streamPlayers.first?.id
        }

        guard let preferredMajorStreamID else {
            preferredMinorStreamID = nil
            return
        }

        let candidateIDs = playback.streamPlayers
            .map(\.id)
            .filter { $0 != preferredMajorStreamID }

        if preferredMinorStreamID == nil
            || candidateIDs.contains(preferredMinorStreamID!) == false {
            preferredMinorStreamID = candidateIDs.first
        }
    }

    private func setLandscapeLayout(_ layout: CanvasVideoLandscapeLayout) {
        let applyLayoutChange = {
            preferredLandscapeLayout = layout

            if layout == .floatingOverlay {
                ensureFloatingSelections()
            }

            floatingMinorOffset = .zero
        }

        if usesVLCBackedPlayback {
            applyLayoutChange()
        } else {
            withAnimation(landscapeLayoutTransitionAnimation) {
                applyLayoutChange()
            }
        }
        showChromeAndScheduleHide()
    }

    private func selectMajorStream(_ id: Int) {
        guard preferredMajorStreamID != id else {
            showChromeAndScheduleHide()
            return
        }

        let applySelectionChange = {
            preferredMajorStreamID = id
            ensureFloatingSelections()
            floatingMinorOffset = .zero
        }

        if usesVLCBackedPlayback {
            applySelectionChange()
        } else {
            withAnimation(majorVideoSwapAnimation) {
                applySelectionChange()
            }
        }

        showChromeAndScheduleHide()
    }

    private func selectMinorStream(_ id: Int) {
        preferredMinorStreamID = id
        ensureFloatingSelections()
        floatingMinorOffset = .zero
        showChromeAndScheduleHide()
    }

    private func fittedAspectSize(
        aspectRatio: CGFloat,
        in containerSize: CGSize
    ) -> CGSize {
        guard containerSize.width > 0, containerSize.height > 0 else {
            return .zero
        }

        let containerAspectRatio = containerSize.width / containerSize.height
        if containerAspectRatio > aspectRatio {
            let height = containerSize.height
            return CGSize(width: height * aspectRatio, height: height)
        } else {
            let width = containerSize.width
            return CGSize(width: width, height: width / aspectRatio)
        }
    }

    private func floatingMinorCardSize(in majorSize: CGSize) -> CGSize {
        let width = min(
            max(majorSize.width * 0.28, 180),
            min(majorSize.width * 0.45, 280)
        )
        return CGSize(width: width, height: width / (16 / 9))
    }

    private func splitLandscapeCardSize(in containerSize: CGSize) -> CGSize {
        guard containerSize.width > 0, containerSize.height > 0 else {
            return .zero
        }

        let horizontalSpacing: CGFloat = 12
        let maxWidth = max((containerSize.width - horizontalSpacing) / 2, 0)
        let heightFromWidth = maxWidth / (16 / 9)

        if heightFromWidth <= containerSize.height {
            return CGSize(width: maxWidth, height: heightFromWidth)
        }

        let height = containerSize.height
        return CGSize(width: height * (16 / 9), height: height)
    }

    private func splitPortraitCardSize(in containerSize: CGSize) -> CGSize {
        guard containerSize.width > 0, containerSize.height > 0 else {
            return .zero
        }

        let verticalSpacing: CGFloat = 12
        let maxHeight = max((containerSize.height - verticalSpacing) / 2, 0)
        let widthFromHeight = maxHeight * (16 / 9)
        let width = min(containerSize.width, widthFromHeight)
        return CGSize(width: width, height: width / (16 / 9))
    }

    private func splitStageCardOffset(
        size: CGSize,
        isLandscape: Bool,
        direction: CGFloat
    ) -> CGSize {
        if isLandscape {
            return CGSize(
                width: direction * ((size.width / 2) + 6),
                height: 0
            )
        }

        return CGSize(
            width: 0,
            height: direction * ((size.height / 2) + 6)
        )
    }

    private func floatingMinorDisplayOffset(
        majorSize: CGSize,
        minorSize: CGSize
    ) -> CGSize {
        let baseOffset = floatingMinorBaseOffset(
            majorSize: majorSize,
            minorSize: minorSize
        )
        let clampedOffset = clampedFloatingMinorOffset(
            proposed: floatingMinorOffset,
            majorSize: majorSize,
            minorSize: minorSize
        )
        return CGSize(
            width: baseOffset.width + clampedOffset.width,
            height: baseOffset.height + clampedOffset.height
        )
    }

    private func floatingMinorBaseOffset(
        majorSize: CGSize,
        minorSize: CGSize
    ) -> CGSize {
        let horizontalTravel = max(
            majorSize.width - minorSize.width - (floatingMinorMargin * 2),
            0
        )
        let verticalTravel = max(
            majorSize.height - minorSize.height - (floatingMinorMargin * 2),
            0
        )
        return CGSize(
            width: horizontalTravel / 2,
            height: -(verticalTravel / 2)
        )
    }

    private func clampedFloatingMinorOffset(
        proposed: CGSize,
        majorSize: CGSize,
        minorSize: CGSize
    ) -> CGSize {
        let horizontalTravel = max(
            majorSize.width - minorSize.width - (floatingMinorMargin * 2),
            0
        )
        let verticalTravel = max(
            majorSize.height - minorSize.height - (floatingMinorMargin * 2),
            0
        )

        return CGSize(
            width: clamp(
                proposed.width,
                minValue: -horizontalTravel,
                maxValue: 0
            ),
            height: clamp(
                proposed.height,
                minValue: 0,
                maxValue: verticalTravel
            )
        )
    }

    private func floatingMinorGesture(
        majorSize: CGSize,
        minorSize: CGSize
    ) -> some Gesture {
        DragGesture()
            .onChanged { value in
                if floatingMinorDragStartOffset == nil {
                    floatingMinorDragStartOffset = floatingMinorOffset
                }

                let baseOffset = floatingMinorDragStartOffset ?? floatingMinorOffset
                floatingMinorOffset = clampedFloatingMinorOffset(
                    proposed: CGSize(
                        width: baseOffset.width + value.translation.width,
                        height: baseOffset.height + value.translation.height
                    ),
                    majorSize: majorSize,
                    minorSize: minorSize
                )
            }
            .onEnded { value in
                let baseOffset = floatingMinorDragStartOffset ?? floatingMinorOffset
                floatingMinorOffset = clampedFloatingMinorOffset(
                    proposed: CGSize(
                        width: baseOffset.width + value.translation.width,
                        height: baseOffset.height + value.translation.height
                    ),
                    majorSize: majorSize,
                    minorSize: minorSize
                )
                floatingMinorDragStartOffset = nil
            }
    }

    private func closePlayer() {
        dismiss()
    }
}

private enum CanvasVideoLandscapeLayout: Equatable {
    case sideBySide
    case floatingOverlay
}

private enum CanvasVideoPlaybackKernel {
    case avPlayer(AVPlayer)
    case vlcPlayer(VLCMediaPlayer)
}

private struct CanvasVideoStreamPlayer: Identifiable {
    let stream: CanvasVideoPlayableStream
    let kernel: CanvasVideoPlaybackKernel

    var id: Int {
        stream.id
    }

    var avPlayer: AVPlayer? {
        guard case let .avPlayer(player) = kernel else {
            return nil
        }
        return player
    }

    var vlcPlayer: VLCMediaPlayer? {
        guard case let .vlcPlayer(player) = kernel else {
            return nil
        }
        return player
    }

    var isSeekable: Bool {
        switch kernel {
        case .avPlayer:
            true
        case let .vlcPlayer(player):
            player.isSeekable
        }
    }

    func play() {
        switch kernel {
        case let .avPlayer(player):
            player.play()
        case let .vlcPlayer(player):
            player.play()
        }
    }

    func pause() {
        switch kernel {
        case let .avPlayer(player):
            player.pause()
        case let .vlcPlayer(player):
            player.pause()
        }
    }

    func stop() {
        switch kernel {
        case let .avPlayer(player):
            player.pause()
        case let .vlcPlayer(player):
            player.stop()
        }
    }

    func beginPrerollIfPossible() {
        guard let player = avPlayer,
              player.rate == 0,
              player.status == .readyToPlay else {
            return
        }

        player.preroll(atRate: 1) { _ in
            // Best-effort warmup only.
        }
    }

    func cancelPendingPrerolls() {
        avPlayer?.cancelPendingPrerolls()
    }

    func cancelPendingSeeks() {
        avPlayer?.currentItem?.cancelPendingSeeks()
    }

    func currentTimeSeconds() -> Double? {
        switch kernel {
        case let .avPlayer(player):
            let seconds = player.currentTime().seconds
            guard seconds.isFinite else {
                return nil
            }
            return max(seconds, 0)
        case let .vlcPlayer(player):
            return CanvasVideoStreamPlayer.seconds(from: player.time)
        }
    }

    func durationSeconds(fallback: Double?) -> Double? {
        switch kernel {
        case let .avPlayer(player):
            let seconds = player.currentItem?.duration.seconds
            guard let seconds, seconds.isFinite, seconds > 0 else {
                return fallback
            }
            return seconds
        case let .vlcPlayer(player):
            return CanvasVideoStreamPlayer.seconds(from: player.media?.length) ?? fallback
        }
    }

    func seek(to seconds: Double) async {
        switch kernel {
        case let .avPlayer(player):
            let targetTime = CMTime(seconds: seconds, preferredTimescale: 600)
            await withCheckedContinuation { continuation in
                player.seek(
                    to: targetTime,
                    toleranceBefore: .zero,
                    toleranceAfter: .zero
                ) { _ in
                    continuation.resume()
                }
            }
        case let .vlcPlayer(player):
            guard isSeekable else {
                return
            }

            player.time = VLCTime(int: Self.clampedMilliseconds(for: seconds))
        }
    }

    private static func clampedMilliseconds(for seconds: Double) -> Int32 {
        let milliseconds = Int((max(seconds, 0) * 1_000).rounded())
        let lowerBound = Int(Int32.min)
        let upperBound = Int(Int32.max)
        return Int32(min(max(milliseconds, lowerBound), upperBound))
    }

    private static func seconds(from time: VLCTime?) -> Double? {
        guard let milliseconds = time?.value?.doubleValue,
              milliseconds.isFinite else {
            return nil
        }

        return max(milliseconds / 1_000, 0)
    }
}

private struct CanvasVideoMenuStreamOption: Identifiable, Equatable {
    let id: Int
    let title: String
}

private struct CanvasVideoControlMenus: View, Equatable {
    let isLandscape: Bool
    let showsSubtitleSettings: Bool
    let subtitlesEnabled: Bool
    let subtitleOffsetIsZero: Bool
    let preferredLandscapeLayout: CanvasVideoLandscapeLayout
    let canUseFloatingLayout: Bool
    let showsFloatingCustomization: Bool
    let streamOptions: [CanvasVideoMenuStreamOption]
    let selectedMajorStreamID: Int?
    let minorStreamOptions: [CanvasVideoMenuStreamOption]
    let selectedMinorStreamID: Int?
    let onSubtitleEnabledChange: (Bool) -> Void
    let onResetSubtitle: () -> Void
    let onSetLandscapeLayout: (CanvasVideoLandscapeLayout) -> Void
    let onSelectMajorStream: (Int) -> Void
    let onSelectMinorStream: (Int) -> Void

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.isLandscape == rhs.isLandscape
            && lhs.showsSubtitleSettings == rhs.showsSubtitleSettings
            && lhs.subtitlesEnabled == rhs.subtitlesEnabled
            && lhs.subtitleOffsetIsZero == rhs.subtitleOffsetIsZero
            && lhs.preferredLandscapeLayout == rhs.preferredLandscapeLayout
            && lhs.canUseFloatingLayout == rhs.canUseFloatingLayout
            && lhs.showsFloatingCustomization == rhs.showsFloatingCustomization
            && lhs.streamOptions == rhs.streamOptions
            && lhs.selectedMajorStreamID == rhs.selectedMajorStreamID
            && lhs.minorStreamOptions == rhs.minorStreamOptions
            && lhs.selectedMinorStreamID == rhs.selectedMinorStreamID
    }

    var body: some View {
        Group {
            if isLandscape {
                HStack(spacing: 12) {
                    if showsSubtitleSettings {
                        subtitleMenu
                    }
                    videoLayoutMenu(isLandscape: true)
                }
            } else {
                combinedSettingsMenu
            }
        }
    }

    private var subtitleMenu: some View {
        Menu {
            subtitleMenuContent()
        } label: {
            menuButtonLabel(
                systemImage: subtitlesEnabled ? "captions.bubble.fill" : "captions.bubble"
            )
        }
    }

    private func videoLayoutMenu(isLandscape: Bool) -> some View {
        Menu {
            videoLayoutMenuContent(isLandscape: isLandscape)
        } label: {
            menuButtonLabel(systemImage: "rectangle.split.2x1")
        }
    }

    private var combinedSettingsMenu: some View {
        Menu {
            if showsSubtitleSettings {
                Menu("字幕") {
                    subtitleMenuContent()
                }
            }

            Menu("视频布局") {
                videoLayoutMenuContent(isLandscape: false)
            }
        } label: {
            menuButtonLabel(systemImage: "ellipsis.circle")
        }
    }

    @ViewBuilder
    private func subtitleMenuContent() -> some View {
        Button {
            onSubtitleEnabledChange(true)
        } label: {
            selectionMenuRow(
                title: "显示字幕",
                isSelected: subtitlesEnabled
            )
        }

        Button {
            onSubtitleEnabledChange(false)
        } label: {
            selectionMenuRow(
                title: "隐藏字幕",
                isSelected: !subtitlesEnabled
            )
        }

        Divider()

        Button {
            onResetSubtitle()
        } label: {
            Text("重置字幕位置")
        }
        .disabled(subtitleOffsetIsZero)
    }

    @ViewBuilder
    private func videoLayoutMenuContent(isLandscape: Bool) -> some View {
        Button {
            onSetLandscapeLayout(.sideBySide)
        } label: {
            selectionMenuRow(
                title: "并排显示",
                isSelected: preferredLandscapeLayout == .sideBySide
            )
        }

        Button {
            onSetLandscapeLayout(.floatingOverlay)
        } label: {
            selectionMenuRow(
                title: "主画面 + 浮窗",
                isSelected: preferredLandscapeLayout == .floatingOverlay
            )
        }
        .disabled(!isLandscape)

        if canUseFloatingLayout, showsFloatingCustomization {
            Divider()

            Menu("主画面") {
                streamSelectionMenuContent(
                    options: streamOptions,
                    selectedID: selectedMajorStreamID,
                    onSelect: onSelectMajorStream
                )
            }

            Menu("浮窗") {
                streamSelectionMenuContent(
                    options: minorStreamOptions,
                    selectedID: selectedMinorStreamID,
                    onSelect: onSelectMinorStream
                )
            }
        }
    }

    @ViewBuilder
    private func streamSelectionMenuContent(
        options: [CanvasVideoMenuStreamOption],
        selectedID: Int?,
        onSelect: @escaping (Int) -> Void
    ) -> some View {
        ForEach(options) { streamOption in
            Button {
                onSelect(streamOption.id)
            } label: {
                selectionMenuRow(
                    title: streamOption.title,
                    isSelected: selectedID == streamOption.id
                )
            }
        }
    }

    private func menuButtonLabel(systemImage: String) -> some View {
        Image(systemName: systemImage)
            .font(.callout.weight(.semibold))
            .foregroundStyle(.white)
            .frame(width: 38, height: 38)
            .background(
                Color.white.opacity(0.08),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
    }

    private func selectionMenuRow(
        title: String,
        isSelected: Bool
    ) -> some View {
        HStack(spacing: 12) {
            Text(title)

            Spacer(minLength: 8)

            if isSelected {
                Image(systemName: "checkmark")
            }
        }
    }
}

private struct CanvasVideoSubtitleOverlaySizePreferenceKey: PreferenceKey {
    static var defaultValue: CGSize = .zero

    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}

private struct CanvasVideoScrubPreviewContext: Sendable {
    let session: CanvasVideoPlatformSession
    let courseId: Int
}

private struct CanvasVideoScrubPreviewSpriteKey: Hashable, Sendable {
    let courseId: Int
    let spriteIndex: Int

    var cacheKey: String {
        "\(courseId)-\(spriteIndex)"
    }
}

private struct CanvasVideoScrubPreviewFrame: Hashable, Sendable {
    static let frameIntervalSeconds: Int = 5
    static let maxRowsPerSprite: Int = 10
    static let maxColumnsPerSprite: Int = 12
    static let maxFramesPerSprite: Int = maxRowsPerSprite * maxColumnsPerSprite

    let courseId: Int
    let spriteIndex: Int
    let frameIndexInSprite: Int
    let frameCountInSprite: Int

    init(
        courseId: Int,
        positionSeconds: Double,
        durationSeconds: Double
    ) {
        let safeDuration = max(durationSeconds, 0)
        let totalFrameCount = max(
            Int(ceil(safeDuration / Double(Self.frameIntervalSeconds))),
            1
        )
        let absoluteFrameIndex = min(
            max(Int(positionSeconds / Double(Self.frameIntervalSeconds)), 0),
            totalFrameCount - 1
        )
        let spriteIndex = absoluteFrameIndex / Self.maxFramesPerSprite

        self.courseId = courseId
        self.spriteIndex = spriteIndex
        self.frameIndexInSprite = absoluteFrameIndex % Self.maxFramesPerSprite

        let remainingFrameCount = totalFrameCount - (spriteIndex * Self.maxFramesPerSprite)
        self.frameCountInSprite = max(
            min(remainingFrameCount, Self.maxFramesPerSprite),
            1
        )
    }

    var spriteKey: CanvasVideoScrubPreviewSpriteKey {
        CanvasVideoScrubPreviewSpriteKey(
            courseId: courseId,
            spriteIndex: spriteIndex
        )
    }

    var cacheKey: String {
        "\(courseId)-\(spriteIndex)-\(frameIndexInSprite)-\(frameCountInSprite)"
    }
}

private struct CanvasVideoScrubber: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let previewContext: CanvasVideoScrubPreviewContext?
    let onEditingChanged: (Bool) -> Void

    @State private var isEditing = false
    @State private var dragTouchOffset: CGFloat?

    private let trackHeight: CGFloat = 8
    private let handleWidth: CGFloat = 28
    private let handleHeight: CGFloat = 18
    private let railInset: CGFloat = 2
    private let interactionAnimation = Animation.spring(response: 0.22, dampingFraction: 0.78)

    private var previewFrame: CanvasVideoScrubPreviewFrame? {
        guard let previewContext else {
            return nil
        }

        return CanvasVideoScrubPreviewFrame(
            courseId: previewContext.courseId,
            positionSeconds: value,
            durationSeconds: range.upperBound
        )
    }

    private var previewTimeText: String {
        let clampedValue = min(max(value, range.lowerBound), range.upperBound)
        return formatPlaybackSeconds(clampedValue)
    }

    var body: some View {
        GeometryReader { geometry in
            let normalizedProgress = normalizedValue(for: value)
            let trackWidth = max(geometry.size.width - handleWidth, 1)
            let handleOffsetX = trackWidth * normalizedProgress
            let handleCenterX = handleOffsetX + (handleWidth / 2)
            let previewOffsetX = previewHorizontalOffset(
                handleCenterX: handleCenterX,
                availableWidth: geometry.size.width
            )

            ZStack(alignment: .leading) {
                trackBackground(width: trackWidth)
                    .padding(.leading, handleWidth / 2)

                progressFill(width: trackWidth * normalizedProgress)
                    .padding(.leading, handleWidth / 2)

                handleView
                    .offset(x: handleOffsetX)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .overlay(alignment: .topLeading) {
                if isEditing,
                   let previewContext,
                   let previewFrame {
                    CanvasVideoScrubPreviewBubble(
                        context: previewContext,
                        frame: previewFrame,
                        currentTimeText: previewTimeText
                    )
                    .offset(
                        x: previewOffsetX,
                        y: -(CanvasVideoScrubPreviewBubble.preferredHeight + 14)
                    )
                    .allowsHitTesting(false)
                    .transition(
                        .opacity.combined(with: .scale(scale: 0.96, anchor: .bottom))
                    )
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        if !isEditing {
                            isEditing = true
                            dragTouchOffset = initialTouchOffset(
                                startLocationX: gesture.startLocation.x,
                                handleCenterX: handleCenterX
                            )
                            onEditingChanged(true)
                        }

                        updateValue(
                            for: gesture.location.x,
                            availableWidth: geometry.size.width,
                            touchOffset: dragTouchOffset ?? 0
                        )
                    }
                    .onEnded { gesture in
                        updateValue(
                            for: gesture.location.x,
                            availableWidth: geometry.size.width,
                            touchOffset: dragTouchOffset ?? 0
                        )
                        dragTouchOffset = nil

                        guard isEditing else {
                            return
                        }

                        isEditing = false
                        onEditingChanged(false)
                    }
            )
        }
        .frame(height: max(handleHeight + 14, 34))
        .transaction { transaction in
            transaction.animation = nil
        }
    }

    private func trackBackground(width: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: trackHeight / 2, style: .continuous)
            .fill(Color.white.opacity(isEditing ? 0.32 : 0.24))
            .overlay {
                RoundedRectangle(cornerRadius: trackHeight / 2, style: .continuous)
                    .stroke(Color.white.opacity(isEditing ? 0.28 : 0.16), lineWidth: 1)
            }
            .frame(width: width, height: trackHeight)
            .shadow(color: .black.opacity(0.24), radius: 8, y: 2)
            .animation(interactionAnimation, value: isEditing)
    }

    private func progressFill(width: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: trackHeight / 2, style: .continuous)
            .fill(Color.white)
            .frame(width: max(width, trackHeight), height: trackHeight)
            .shadow(color: .white.opacity(isEditing ? 0.5 : 0.3), radius: isEditing ? 8 : 5)
            .shadow(color: .black.opacity(0.28), radius: 10, y: 2)
            .animation(interactionAnimation, value: isEditing)
    }

    private var handleView: some View {
        RoundedRectangle(cornerRadius: handleHeight / 2.2, style: .continuous)
            .fill(Color.white)
            .frame(width: handleWidth, height: handleHeight)
            .overlay {
                RoundedRectangle(cornerRadius: handleHeight / 2.2, style: .continuous)
                    .stroke(Color.white.opacity(0.88), lineWidth: 1.2)
                    .padding(railInset)
            }
            .shadow(color: .white.opacity(isEditing ? 0.42 : 0.24), radius: isEditing ? 10 : 6)
            .shadow(color: .black.opacity(0.34), radius: 12, y: 4)
            .scaleEffect(isEditing ? 1.1 : 1)
        .animation(interactionAnimation, value: isEditing)
    }

    private var rangeSpan: Double {
        max(range.upperBound - range.lowerBound, .leastNonzeroMagnitude)
    }

    private func normalizedValue(for value: Double) -> CGFloat {
        let clampedValue = min(max(value, range.lowerBound), range.upperBound)
        return CGFloat((clampedValue - range.lowerBound) / rangeSpan)
    }

    private func initialTouchOffset(
        startLocationX: CGFloat,
        handleCenterX: CGFloat
    ) -> CGFloat {
        let offset = startLocationX - handleCenterX
        return abs(offset) <= (handleWidth / 2) ? offset : 0
    }

    private func updateValue(
        for locationX: CGFloat,
        availableWidth: CGFloat,
        touchOffset: CGFloat
    ) {
        let trackWidth = max(availableWidth - handleWidth, 1)
        let handleCenterX = min(
            max(locationX - touchOffset, handleWidth / 2),
            trackWidth + (handleWidth / 2)
        )
        let progress = (handleCenterX - (handleWidth / 2)) / trackWidth
        value = range.lowerBound + (Double(progress) * rangeSpan)
    }

    private func previewHorizontalOffset(
        handleCenterX: CGFloat,
        availableWidth: CGFloat
    ) -> CGFloat {
        let halfPreviewWidth = CanvasVideoScrubPreviewBubble.preferredWidth / 2
        let unclampedOffset = handleCenterX - halfPreviewWidth
        return min(
            max(unclampedOffset, 0),
            max(availableWidth - CanvasVideoScrubPreviewBubble.preferredWidth, 0)
        )
    }
}

private struct CanvasVideoScrubPreviewBubble: View {
    static let preferredWidth: CGFloat = 176
    static let imageHeight: CGFloat = 99
    static let preferredHeight: CGFloat = imageHeight + 16

    let context: CanvasVideoScrubPreviewContext
    let frame: CanvasVideoScrubPreviewFrame
    let currentTimeText: String

    @State private var previewImage: UIImage?
    @State private var displayedFrame: CanvasVideoScrubPreviewFrame?
    @State private var imageOpacity: Double = 0
    @State private var isLoading: Bool = false
    @State private var loadFailed: Bool = false

    private static let maxImageRetryCount: Int = 1

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.black.opacity(0.92))

            Group {
                if let previewImage, displayedFrame == frame {
                    Image(uiImage: previewImage)
                        .resizable()
                        .scaledToFill()
                        .opacity(imageOpacity)
                } else if loadFailed {
                    CanvasVideoScrubPreviewPlaceholder(systemImage: "photo.badge.exclamationmark")
                } else {
                    ProgressView()
                        .tint(.white)
                }
            }
            .frame(width: Self.preferredWidth, height: Self.imageHeight)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            Text(currentTimeText)
                .font(.caption2.monospacedDigit().weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(.black.opacity(0.6), in: Capsule())
                .padding(10)
        }
        .frame(width: Self.preferredWidth, height: Self.imageHeight)
        .shadow(color: .black.opacity(0.3), radius: 18, y: 8)
        .task(id: frame) {
            await loadPreviewIfNeeded()
        }
    }

    @MainActor
    private func loadPreviewIfNeeded() async {
        guard displayedFrame != frame || previewImage == nil else {
            return
        }

        if let cachedImage = await CanvasVideoScrubPreviewLoader.shared.cachedImage(for: frame) {
            showPreview(cachedImage, for: frame)
            loadFailed = false
            return
        }

        isLoading = true
        loadFailed = false
        previewImage = nil
        imageOpacity = 0

        defer {
            isLoading = false
        }

        do {
            let image = try await CanvasVideoScrubPreviewLoader.shared.image(
                for: frame,
                session: context.session,
                maxRetryCount: Self.maxImageRetryCount
            )
            guard !Task.isCancelled else {
                return
            }

            showPreview(image, for: frame)
            loadFailed = false
        } catch is CancellationError {
            // A newer preview request has taken priority.
        } catch {
            guard !Task.isCancelled else {
                return
            }

            displayedFrame = frame
            previewImage = nil
            imageOpacity = 0
            loadFailed = true
        }
    }

    @MainActor
    private func showPreview(
        _ image: UIImage,
        for frame: CanvasVideoScrubPreviewFrame
    ) {
        displayedFrame = frame
        previewImage = image
        imageOpacity = 0

        withAnimation(.easeInOut(duration: 0.18)) {
            imageOpacity = 1
        }
    }
}

private struct CanvasVideoScrubPreviewPlaceholder: View {
    let systemImage: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.title3.weight(.medium))

            Text("拖动预览")
                .font(.caption)
        }
        .foregroundStyle(.white.opacity(0.72))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private actor CanvasVideoScrubPreviewLoader {
    static let shared = CanvasVideoScrubPreviewLoader()

    private let frameCache = NSCache<NSString, UIImage>()
    private let spriteSheetCache = NSCache<NSString, UIImage>()
    private var spriteURLCache: [CanvasVideoScrubPreviewSpriteKey: URL] = [:]
    private var inFlightFrameTasks: [CanvasVideoScrubPreviewFrame: Task<UIImage, Error>] = [:]
    private var inFlightSpriteURLTasks: [CanvasVideoScrubPreviewSpriteKey: Task<URL, Error>] = [:]
    private var inFlightSpriteSheetTasks: [CanvasVideoScrubPreviewSpriteKey: Task<UIImage, Error>] = [:]

    func cachedImage(for frame: CanvasVideoScrubPreviewFrame) -> UIImage? {
        frameCache.object(forKey: frame.cacheKey as NSString)
    }

    func image(
        for frame: CanvasVideoScrubPreviewFrame,
        session: CanvasVideoPlatformSession,
        maxRetryCount: Int
    ) async throws -> UIImage {
        if let cachedImage = cachedImage(for: frame) {
            return cachedImage
        }

        if let existingTask = inFlightFrameTasks[frame] {
            return try await existingTask.value
        }

        let task = Task.detached(priority: .utility) {
            let spriteSheet = try await CanvasVideoScrubPreviewLoader.shared.spriteSheet(
                for: frame.spriteKey,
                session: session,
                maxRetryCount: maxRetryCount
            )

            return try CanvasVideoScrubPreviewLoader.cropFrame(
                from: spriteSheet,
                frameIndexInSprite: frame.frameIndexInSprite,
                frameCountInSprite: frame.frameCountInSprite
            )
        }

        inFlightFrameTasks[frame] = task

        do {
            let image = try await task.value
            frameCache.setObject(image, forKey: frame.cacheKey as NSString)
            inFlightFrameTasks[frame] = nil
            return image
        } catch {
            inFlightFrameTasks[frame] = nil
            throw error
        }
    }

    private func spriteSheet(
        for spriteKey: CanvasVideoScrubPreviewSpriteKey,
        session: CanvasVideoPlatformSession,
        maxRetryCount: Int
    ) async throws -> UIImage {
        if let cachedImage = spriteSheetCache.object(forKey: spriteKey.cacheKey as NSString) {
            return cachedImage
        }

        if let existingTask = inFlightSpriteSheetTasks[spriteKey] {
            return try await existingTask.value
        }

        let task = Task.detached(priority: .utility) {
            let url = try await CanvasVideoScrubPreviewLoader.shared.spriteURL(
                for: spriteKey,
                session: session
            )
            return try await CanvasVideoScrubPreviewLoader.fetchImage(
                from: url,
                maxRetryCount: maxRetryCount
            )
        }

        inFlightSpriteSheetTasks[spriteKey] = task

        do {
            let image = try await task.value
            spriteSheetCache.setObject(image, forKey: spriteKey.cacheKey as NSString)
            inFlightSpriteSheetTasks[spriteKey] = nil
            return image
        } catch {
            inFlightSpriteSheetTasks[spriteKey] = nil
            throw error
        }
    }

    private func spriteURL(
        for spriteKey: CanvasVideoScrubPreviewSpriteKey,
        session: CanvasVideoPlatformSession
    ) async throws -> URL {
        if let cachedURL = spriteURLCache[spriteKey] {
            return cachedURL
        }

        if let existingTask = inFlightSpriteURLTasks[spriteKey] {
            return try await existingTask.value
        }

        let task = Task.detached(priority: .utility) {
            try await CanvasVideoPlatformAPI.fetchSpriteImageURL(
                session: session,
                courseId: spriteKey.courseId,
                spriteIndex: spriteKey.spriteIndex
            )
        }

        inFlightSpriteURLTasks[spriteKey] = task

        do {
            let url = try await task.value
            spriteURLCache[spriteKey] = url
            inFlightSpriteURLTasks[spriteKey] = nil
            return url
        } catch {
            inFlightSpriteURLTasks[spriteKey] = nil
            throw error
        }
    }

    private static func fetchImage(
        from url: URL,
        maxRetryCount: Int
    ) async throws -> UIImage {
        var attempt = 0

        while true {
            do {
                return try await requestImage(from: url)
            } catch {
                guard attempt < maxRetryCount else {
                    throw error
                }

                let backoffSeconds = UInt64(1 << attempt)
                attempt += 1
                try await Task.sleep(nanoseconds: backoffSeconds * 1_000_000_000)
            }
        }
    }

    private static func requestImage(from url: URL) async throws -> UIImage {
        var request = URLRequest(url: url)
        request.cachePolicy = .returnCacheDataElseLoad
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw CanvasVideoScrubPreviewLoaderError.badResponse(url)
        }
        guard let image = UIImage(data: data) else {
            throw CanvasVideoScrubPreviewLoaderError.invalidImageData(url)
        }

        return image
    }

    private static func cropFrame(
        from spriteSheet: UIImage,
        frameIndexInSprite: Int,
        frameCountInSprite: Int
    ) throws -> UIImage {
        guard let cgImage = spriteSheet.cgImage else {
            throw CanvasVideoScrubPreviewLoaderError.invalidSpriteSheet
        }

        let layout = inferredGridLayout(
            imageSize: CGSize(
                width: CGFloat(cgImage.width),
                height: CGFloat(cgImage.height)
            ),
            frameCount: frameCountInSprite
        )

        let row = frameIndexInSprite / layout.columns
        let column = frameIndexInSprite % layout.columns
        guard row < layout.rows else {
            throw CanvasVideoScrubPreviewLoaderError.invalidFrameLayout
        }

        let cellWidth = CGFloat(cgImage.width) / CGFloat(layout.columns)
        let cellHeight = CGFloat(cgImage.height) / CGFloat(layout.rows)
        let cropRect = CGRect(
            x: CGFloat(column) * cellWidth,
            y: CGFloat(row) * cellHeight,
            width: cellWidth,
            height: cellHeight
        )
        .integral

        guard let croppedImage = cgImage.cropping(to: cropRect) else {
            throw CanvasVideoScrubPreviewLoaderError.invalidFrameLayout
        }

        return UIImage(
            cgImage: croppedImage,
            scale: spriteSheet.scale,
            orientation: spriteSheet.imageOrientation
        )
    }

    private static func inferredGridLayout(
        imageSize: CGSize,
        frameCount: Int
    ) -> (columns: Int, rows: Int) {
        let candidateCount = max(
            min(frameCount, CanvasVideoScrubPreviewFrame.maxColumnsPerSprite),
            1
        )
        let expectedFrameAspectRatio: CGFloat = 16 / 9
        var bestLayout = (
            columns: candidateCount,
            rows: max(
                Int(
                    ceil(
                        Double(frameCount)
                            / Double(candidateCount)
                    )
                ),
                1
            ),
            score: CGFloat.greatestFiniteMagnitude
        )

        for columns in 1...candidateCount {
            let rows = max(
                Int(
                    ceil(
                        Double(frameCount)
                            / Double(columns)
                    )
                ),
                1
            )
            guard rows <= CanvasVideoScrubPreviewFrame.maxRowsPerSprite else {
                continue
            }

            let cellAspectRatio = (imageSize.width / CGFloat(columns))
                / (imageSize.height / CGFloat(rows))
            let score = abs(cellAspectRatio - expectedFrameAspectRatio)

            if score < bestLayout.score {
                bestLayout = (
                    columns: columns,
                    rows: rows,
                    score: score
                )
            }
        }

        return (
            columns: bestLayout.columns,
            rows: bestLayout.rows
        )
    }
}

private enum CanvasVideoScrubPreviewLoaderError: Error {
    case badResponse(URL)
    case invalidImageData(URL)
    case invalidSpriteSheet
    case invalidFrameLayout
}

@MainActor
private final class CanvasVideoPlaybackCoordinator: ObservableObject {
    private struct NowPlayingSnapshot: Equatable {
        let elapsedTimeSecond: Int
        let durationSecond: Int?
        let playbackRate: Double
        let wantsPlayback: Bool
        let isPlaying: Bool
        let isBuffering: Bool
        let canSeek: Bool
    }

    @Published private(set) var currentTime: Double
    @Published private(set) var duration: Double
    @Published private(set) var isPlaying: Bool = false
    @Published private(set) var isBuffering: Bool = false
    @Published private(set) var activeSubtitleText: String?
    @Published private(set) var showsPauseButton: Bool = false

    private let title: String
    private let subtitle: String?
    let streamPlayers: [CanvasVideoStreamPlayer]

    var primaryStreamPlayer: CanvasVideoStreamPlayer? {
        streamPlayers.first
    }

    var secondaryStreamPlayers: [CanvasVideoStreamPlayer] {
        Array(streamPlayers.dropFirst())
    }

    private let seekTimescale: CMTimeScale = 600
    private let playbackCompletionTolerance: Double = 0.25
    private let coordinationMedium = AVPlaybackCoordinationMedium()
    private let isLiveMode: Bool
    private let playsViaAVFoundationOnly: Bool
    private var subtitleSegments: [CanvasVideoTranscriptSegment]
    private var durationHintSeconds: Double?
    private var timeObserverToken: Any?
    private var timeControlObservation: NSKeyValueObservation?
    private var itemStatusObservation: NSKeyValueObservation?
    private var endObserver: NSObjectProtocol?
    private var vlcTimeObserver: NSObjectProtocol?
    private var vlcStateObserver: NSObjectProtocol?
    private var sharedStateMonitorTask: Task<Void, Never>?
    private var bufferingStreamIDs: Set<Int> = []
    private var wasPlayingBeforeScrub: Bool = false
    private var isAwaitingPlaybackAfterScrub: Bool = false
    private var seekRequestID: UInt64 = 0
    private var wantsPlayback: Bool = false
    private var preservesPlayingStatusWhileScrubbing: Bool = false
    #if os(iOS)
    private let remoteSkipInterval = NSNumber(value: 15)
    private var remoteCommandTargets: [(command: MPRemoteCommand, target: Any)] = []
    private var lastNowPlayingSnapshot: NowPlayingSnapshot?
    #endif

    init(
        title: String,
        subtitle: String?,
        streams: [CanvasVideoPlayableStream],
        subtitles: [CanvasVideoTranscriptSegment],
        durationHintSeconds: Int?,
        isLiveMode: Bool
    ) {
        self.title = title
        self.subtitle = subtitle
        self.streamPlayers = streams.enumerated().map { index, stream in
            if stream.format.supportsAVPlayer {
                let playerItem = AVPlayerItem(url: stream.url)
                let player = AVPlayer(playerItem: playerItem)
                player.actionAtItemEnd = .pause
                player.allowsExternalPlayback = index == 0
                player.preventsDisplaySleepDuringVideoPlayback = index == 0
                player.isMuted = index != 0
                player.networkResourcePriority = index == 0 ? .high : .default

                return CanvasVideoStreamPlayer(
                    stream: stream,
                    kernel: .avPlayer(player)
                )
            }

            let media = VLCMedia(url: stream.url)
            let player = VLCMediaPlayer()
            player.media = media
            player.audio?.isMuted = index != 0

            return CanvasVideoStreamPlayer(
                stream: stream,
                kernel: .vlcPlayer(player)
            )
        }
        self.isLiveMode = isLiveMode
        self.playsViaAVFoundationOnly = self.streamPlayers.allSatisfy { $0.avPlayer != nil }
        self.subtitleSegments = Self.sortedSubtitles(subtitles)
        self.durationHintSeconds = durationHintSeconds.map(Double.init)
        self.currentTime = 0
        self.duration = durationHintSeconds.map(Double.init) ?? 0
        configurePlaybackCoordinationMedium()
        configureObservers()
    }

    deinit {
        sharedStateMonitorTask?.cancel()
        sharedStateMonitorTask = nil
        bufferingStreamIDs.removeAll()

        if let timeObserverToken, let primaryPlayer = streamPlayers.first?.avPlayer {
            primaryPlayer.removeTimeObserver(timeObserverToken)
        }

        if playsViaAVFoundationOnly {
            streamPlayers.compactMap(\.avPlayer).forEach { player in
                try? player.playbackCoordinator.coordinate(using: nil)
            }
        }

        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }

        if let vlcTimeObserver {
            NotificationCenter.default.removeObserver(vlcTimeObserver)
        }

        if let vlcStateObserver {
            NotificationCenter.default.removeObserver(vlcStateObserver)
        }

        streamPlayers.forEach { $0.stop() }
    }

    func startPlayback() {
        guard let primaryStreamPlayer else {
            return
        }

        wantsPlayback = true
        startSharedStateMonitorIfNeeded()
        configureAudioSessionIfNeeded()
        configureRemoteCommandsIfNeeded()
        cancelPendingPrerolls()

        if playsViaAVFoundationOnly, let primaryPlayer = primaryStreamPlayer.avPlayer {
            syncPlaybackState(for: primaryPlayer)
            resumePrimaryPlayerIfNeeded(primaryPlayer)
            syncPlaybackState(for: primaryPlayer)
            return
        }

        for streamPlayer in streamPlayers {
            switch streamPlayer.kernel {
            case let .avPlayer(player):
                if shouldUseImmediateResume(for: player) {
                    player.playImmediately(atRate: 1)
                } else {
                    player.play()
                }
            case let .vlcPlayer(player):
                player.play()
            }
        }

        syncPrimaryPlaybackState()
    }

    func stopPlayback(prepareForResume: Bool = true) {
        isAwaitingPlaybackAfterScrub = false
        preservesPlayingStatusWhileScrubbing = false
        wantsPlayback = false
        stopSharedStateMonitor()

        if prepareForResume {
            streamPlayers.forEach { $0.pause() }
        } else {
            streamPlayers.forEach { $0.stop() }
        }

        syncPrimaryPlaybackState()

        if prepareForResume {
            beginPrerollForPausedPlayers()
        } else {
            tearDownNowPlayingSession()
        }
    }

    func togglePlayback() {
        if wantsPlayback {
            stopPlayback()
        } else {
            if hasReachedPlaybackEnd(at: currentTime) {
                wasPlayingBeforeScrub = true
                Task {
                    await completeScrubbing(at: 0)
                }
                return
            }

            startPlayback()
        }
    }

    func skip(by delta: Double) {
        guard !isLiveMode,
              let primaryStreamPlayer,
              primaryStreamPlayer.isSeekable else {
            return
        }

        let resumePlayback = wantsPlayback
        Task {
            await performSeek(
                to: currentTime + delta,
                resumePlayback: resumePlayback
            )
        }
    }

    func beginScrubbing() {
        guard !isLiveMode,
              let primaryStreamPlayer,
              primaryStreamPlayer.isSeekable else {
            return
        }

        isAwaitingPlaybackAfterScrub = false
        wasPlayingBeforeScrub = wantsPlayback
        preservesPlayingStatusWhileScrubbing = wantsPlayback
        invalidatePendingSeekRequests()
        cancelPendingPrerolls()

        if playsViaAVFoundationOnly, let primaryPlayer = primaryStreamPlayer.avPlayer {
            primaryPlayer.pause()
            syncPlaybackState(for: primaryPlayer)
            return
        }

        streamPlayers.forEach { $0.pause() }
        syncPrimaryPlaybackState()
    }

    func completeScrubbing(at seconds: Double) async {
        isAwaitingPlaybackAfterScrub = wasPlayingBeforeScrub
        preservesPlayingStatusWhileScrubbing = false

        if isAwaitingPlaybackAfterScrub {
            showsPauseButton = true
            isPlaying = true
            isBuffering = true
        }

        await performSeek(
            to: seconds,
            resumePlayback: wasPlayingBeforeScrub
        )
    }

    func updateSubtitles(_ subtitles: [CanvasVideoTranscriptSegment]) {
        subtitleSegments = Self.sortedSubtitles(subtitles)
        updateActiveSubtitle(at: currentTime)
    }

    func updateDurationHint(seconds: Int?) {
        durationHintSeconds = seconds.map(Double.init)
        if duration <= 0 {
            duration = durationHintSeconds ?? 0
        }
        updateNowPlayingInfoIfNeeded(force: true)
    }

    private func configureObservers() {
        if let primaryPlayer = primaryStreamPlayer?.avPlayer {
            timeObserverToken = primaryPlayer.addPeriodicTimeObserver(
                forInterval: CMTime(seconds: 0.25, preferredTimescale: seekTimescale),
                queue: .main
            ) { [weak self] time in
                Task { @MainActor in
                    self?.handlePeriodicTimeUpdate(time)
                }
            }

            timeControlObservation = primaryPlayer.observe(
                \.timeControlStatus,
                options: [.initial, .new]
            ) { [weak self] player, _ in
                Task { @MainActor in
                    self?.syncPlaybackState(for: player)
                }
            }

            if let primaryItem = primaryPlayer.currentItem {
                itemStatusObservation = primaryItem.observe(
                    \.status,
                    options: [.initial, .new]
                ) { [weak self] item, _ in
                    Task { @MainActor in
                        self?.handlePrimaryItemStatusChange(item.status)
                    }
                }
            }

            endObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: primaryPlayer.currentItem,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.handlePlaybackEnded()
                }
            }
            return
        }

        guard let primaryPlayer = primaryStreamPlayer?.vlcPlayer else {
            return
        }

        vlcTimeObserver = NotificationCenter.default.addObserver(
            forName: Notification.Name(rawValue: VLCMediaPlayerTimeChanged as String),
            object: primaryPlayer,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleVLCTimeUpdate()
            }
        }

        vlcStateObserver = NotificationCenter.default.addObserver(
            forName: Notification.Name(rawValue: VLCMediaPlayerStateChanged as String),
            object: primaryPlayer,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleVLCStateChange()
            }
        }

        syncPlaybackState(for: primaryPlayer)
    }

    private func handlePeriodicTimeUpdate(_ time: CMTime) {
        let previousDuration = duration
        let seconds = max(time.seconds, 0)
        guard seconds.isFinite else {
            return
        }

        currentTime = seconds

        if let resolvedDuration = resolvedDuration {
            duration = max(resolvedDuration, currentTime)
        }

        updateActiveSubtitle(at: seconds)

        if previousDuration <= 0, duration > 0 {
            updateNowPlayingInfoIfNeeded(force: true)
        }
    }

    private func handleVLCTimeUpdate() {
        let previousDuration = duration
        guard let seconds = primaryStreamPlayer?.currentTimeSeconds() else {
            return
        }

        currentTime = seconds

        if let resolvedDuration = resolvedDuration {
            duration = max(resolvedDuration, currentTime)
        }

        updateActiveSubtitle(at: seconds)

        if previousDuration <= 0, duration > 0 {
            updateNowPlayingInfoIfNeeded(force: true)
        }
    }

    private func syncPrimaryPlaybackState() {
        if playsViaAVFoundationOnly, streamPlayers.count > 1 {
            refreshSharedPlaybackState()
            return
        }

        guard let primaryStreamPlayer else {
            isPlaying = false
            isBuffering = false
            showsPauseButton = false
            return
        }

        if let player = primaryStreamPlayer.avPlayer {
            syncPlaybackState(for: player)
        } else if let player = primaryStreamPlayer.vlcPlayer {
            syncPlaybackState(for: player)
        }
    }

    private func syncPlaybackState(for player: AVPlayer) {
        defer {
            updateNowPlayingInfoIfNeeded()
        }

        let itemHasFailed = player.currentItem?.status == .failed

        if isAwaitingPlaybackAfterScrub {
            if !wantsPlayback || itemHasFailed {
                isAwaitingPlaybackAfterScrub = false
            } else if player.timeControlStatus == .paused {
                showsPauseButton = true
                isPlaying = true
                isBuffering = true
                return
            } else {
                isAwaitingPlaybackAfterScrub = false
            }
        }

        if preservesPlayingStatusWhileScrubbing {
            if wantsPlayback, !itemHasFailed, player.timeControlStatus == .paused {
                showsPauseButton = true
                isPlaying = true
                isBuffering = false
                return
            }

            preservesPlayingStatusWhileScrubbing = false
        }

        if !itemHasFailed,
           player.timeControlStatus == .paused,
           !shouldTreatPausedStateAsBuffering(for: player),
           handlePlaybackEndedIfNeeded(at: currentPlaybackPosition(for: player)) {
            return
        }

        showsPauseButton = wantsPlayback

        switch player.timeControlStatus {
        case .paused:
            if shouldTreatPausedStateAsBuffering(for: player) {
                isPlaying = true
                isBuffering = true
            } else {
                isPlaying = false
                isBuffering = false
            }
        case .waitingToPlayAtSpecifiedRate:
            isPlaying = wantsPlayback
            isBuffering = wantsPlayback
        case .playing:
            isPlaying = true
            isBuffering = false
        @unknown default:
            isPlaying = false
            isBuffering = false
        }
    }

    private func syncPlaybackState(for player: VLCMediaPlayer) {
        defer {
            updateNowPlayingInfoIfNeeded()
        }

        if isAwaitingPlaybackAfterScrub {
            if !wantsPlayback {
                isAwaitingPlaybackAfterScrub = false
            } else if player.state == .paused {
                showsPauseButton = true
                isPlaying = true
                isBuffering = true
                return
            } else {
                isAwaitingPlaybackAfterScrub = false
            }
        }

        if preservesPlayingStatusWhileScrubbing {
            if wantsPlayback, player.state == .paused {
                showsPauseButton = true
                isPlaying = true
                isBuffering = false
                return
            }

            preservesPlayingStatusWhileScrubbing = false
        }

        showsPauseButton = wantsPlayback

        if player.isPlaying {
            isPlaying = true
            isBuffering = false
            return
        }

        switch player.state {
        case .opening, .buffering:
            isPlaying = wantsPlayback
            isBuffering = wantsPlayback
        case .esAdded:
            isPlaying = player.isPlaying || wantsPlayback
            isBuffering = false
        case .playing:
            isPlaying = true
            isBuffering = false
        case .paused, .stopped, .ended, .error:
            isPlaying = false
            isBuffering = false
        @unknown default:
            isPlaying = false
            isBuffering = false
        }
    }

    private func handlePrimaryItemStatusChange(_ status: AVPlayerItem.Status) {
        guard let primaryPlayer = primaryStreamPlayer?.avPlayer else {
            return
        }

        if wantsPlayback, status == .readyToPlay, primaryPlayer.timeControlStatus == .paused {
            resumePrimaryPlayerIfNeeded(primaryPlayer)
        }

        syncPlaybackState(for: primaryPlayer)
    }

    private func handleVLCStateChange() {
        guard let player = primaryStreamPlayer?.vlcPlayer else {
            return
        }

        if player.state == .ended {
            handlePlaybackEnded()
            return
        }

        syncPlaybackState(for: player)
    }

    private func handlePlaybackEnded() {
        isAwaitingPlaybackAfterScrub = false
        stopPlayback(prepareForResume: false)
        currentTime = duration
        updateActiveSubtitle(at: currentTime)
    }

    private func updateActiveSubtitle(at seconds: Double) {
        let milliseconds = Int(seconds * 1_000)
        activeSubtitleText = subtitleSegments.first(where: { segment in
            guard let start = segment.bg else {
                return false
            }

            let end = segment.ed ?? start + 3_000
            return milliseconds >= start && milliseconds <= end
        })?.text
    }

    private func performSeek(to requestedSeconds: Double, resumePlayback: Bool) async {
        let requestID = nextSeekRequestID()
        await seek(
            to: requestedSeconds,
            resumePlayback: resumePlayback,
            requestID: requestID
        )
    }

    private func seek(
        to requestedSeconds: Double,
        resumePlayback: Bool,
        requestID: UInt64
    ) async {
        let maxDuration = max(resolvedDuration ?? 0, requestedSeconds, 0)
        let clampedSeconds = min(max(requestedSeconds, 0), maxDuration)

        for streamPlayer in streamPlayers {
            await streamPlayer.seek(to: clampedSeconds)
        }

        guard requestID == seekRequestID else {
            return
        }

        currentTime = clampedSeconds
        updateActiveSubtitle(at: clampedSeconds)
        updateNowPlayingInfoIfNeeded(force: true)

        if resumePlayback {
            startPlayback()
        }
    }

    private func nextSeekRequestID() -> UInt64 {
        seekRequestID &+= 1
        cancelPendingSeeks()
        return seekRequestID
    }

    private func invalidatePendingSeekRequests() {
        seekRequestID &+= 1
        cancelPendingSeeks()
    }

    private var resolvedDuration: Double? {
        guard let duration = primaryStreamPlayer?.durationSeconds(fallback: durationHintSeconds),
              duration.isFinite,
              duration > 0 else {
            return durationHintSeconds
        }

        return duration
    }

    private func hasReachedPlaybackEnd(at seconds: Double) -> Bool {
        guard let resolvedDuration,
              resolvedDuration > 0 else {
            return false
        }

        return seconds >= max(resolvedDuration - playbackCompletionTolerance, 0)
    }

    private func currentPlaybackPosition(for player: AVPlayer) -> Double {
        let seconds = player.currentTime().seconds
        guard seconds.isFinite else {
            return currentTime
        }

        return max(currentTime, max(seconds, 0))
    }

    private func handlePlaybackEndedIfNeeded(at seconds: Double) -> Bool {
        guard wantsPlayback,
              !isAwaitingPlaybackAfterScrub,
              !preservesPlayingStatusWhileScrubbing,
              hasReachedPlaybackEnd(at: seconds) else {
            return false
        }

        handlePlaybackEnded()
        return true
    }

    private func configureAudioSessionIfNeeded() {
        #if os(iOS)
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            // Playback can continue even if the session cannot be promoted.
        }
        #endif
    }

    private func deactivateAudioSessionIfNeeded() {
        #if os(iOS)
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        } catch {
            // Allow teardown to continue even if session deactivation fails.
        }
        #endif
    }

    private func beginPrerollForPausedPlayers() {
        streamPlayers.forEach { $0.beginPrerollIfPossible() }
    }

    private func cancelPendingPrerolls() {
        streamPlayers.forEach { $0.cancelPendingPrerolls() }
    }

    private func cancelPendingSeeks() {
        streamPlayers.forEach { $0.cancelPendingSeeks() }
    }

    private func shouldUseImmediateResume(for player: AVPlayer) -> Bool {
        guard let item = player.currentItem else {
            return false
        }

        return item.isPlaybackLikelyToKeepUp
            || item.isPlaybackBufferFull
            || !item.isPlaybackBufferEmpty
    }

    private func shouldTreatPausedStateAsBuffering(for player: AVPlayer) -> Bool {
        guard wantsPlayback, let item = player.currentItem else {
            return false
        }

        if item.status == .failed {
            return false
        }

        if hasReachedPlaybackEnd(at: currentPlaybackPosition(for: player)) {
            return false
        }

        return player.reasonForWaitingToPlay != nil
            || item.status != .readyToPlay
            || item.isPlaybackBufferEmpty
    }

    private func resumePrimaryPlayerIfNeeded(_ player: AVPlayer) {
        if streamPlayers.count == 1, shouldUseImmediateResume(for: player) {
            player.playImmediately(atRate: 1)
        } else {
            // For multiview playback, favor AVFoundation's coordinated startup so all
            // players resume together instead of letting one run ahead and forcing catch-up.
            player.play()
        }
    }

    private func configurePlaybackCoordinationMedium() {
        guard playsViaAVFoundationOnly else {
            return
        }

        for player in streamPlayers.compactMap(\.avPlayer) {
            do {
                try player.playbackCoordinator.coordinate(using: coordinationMedium)
            } catch {
                // Keep the player usable even if local coordination setup fails.
            }
        }
    }

    private func configureRemoteCommandsIfNeeded() {
        #if os(iOS)
        let commandCenter = MPRemoteCommandCenter.shared()

        guard remoteCommandTargets.isEmpty else {
            updateRemoteCommandAvailability(commandCenter)
            return
        }

        remoteCommandTargets.append(
            (
                commandCenter.playCommand,
                commandCenter.playCommand.addTarget { [weak self] _ in
                    guard let self else {
                        return .commandFailed
                    }

                    Task { @MainActor in
                        self.startPlayback()
                    }
                    return .success
                }
            )
        )
        remoteCommandTargets.append(
            (
                commandCenter.pauseCommand,
                commandCenter.pauseCommand.addTarget { [weak self] _ in
                    guard let self else {
                        return .commandFailed
                    }

                    Task { @MainActor in
                        self.stopPlayback()
                    }
                    return .success
                }
            )
        )
        remoteCommandTargets.append(
            (
                commandCenter.togglePlayPauseCommand,
                commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
                    guard let self else {
                        return .commandFailed
                    }

                    Task { @MainActor in
                        self.togglePlayback()
                    }
                    return .success
                }
            )
        )
        remoteCommandTargets.append(
            (
                commandCenter.skipForwardCommand,
                commandCenter.skipForwardCommand.addTarget { [weak self] _ in
                    guard let self, self.canSeekRemotely else {
                        return .commandFailed
                    }

                    Task { @MainActor in
                        self.skip(by: self.remoteSkipInterval.doubleValue)
                    }
                    return .success
                }
            )
        )
        remoteCommandTargets.append(
            (
                commandCenter.skipBackwardCommand,
                commandCenter.skipBackwardCommand.addTarget { [weak self] _ in
                    guard let self, self.canSeekRemotely else {
                        return .commandFailed
                    }

                    Task { @MainActor in
                        self.skip(by: -self.remoteSkipInterval.doubleValue)
                    }
                    return .success
                }
            )
        )
        remoteCommandTargets.append(
            (
                commandCenter.changePlaybackPositionCommand,
                commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
                    guard let self,
                          self.canSeekRemotely,
                          let positionEvent = event as? MPChangePlaybackPositionCommandEvent else {
                        return .commandFailed
                    }

                    Task { @MainActor in
                        self.wasPlayingBeforeScrub = self.wantsPlayback
                        await self.completeScrubbing(at: positionEvent.positionTime)
                    }
                    return .success
                }
            )
        )

        commandCenter.skipForwardCommand.preferredIntervals = [remoteSkipInterval]
        commandCenter.skipBackwardCommand.preferredIntervals = [remoteSkipInterval]
        updateRemoteCommandAvailability(commandCenter)
        #endif
    }

    private func updateRemoteCommandAvailability(
        _ commandCenter: MPRemoteCommandCenter = MPRemoteCommandCenter.shared(),
        isSessionActive: Bool? = nil
    ) {
        #if os(iOS)
        let hasActivePlayer = isSessionActive ?? (primaryStreamPlayer != nil)
        let canSeekRemotely = hasActivePlayer && self.canSeekRemotely

        commandCenter.playCommand.isEnabled = hasActivePlayer
        commandCenter.pauseCommand.isEnabled = hasActivePlayer
        commandCenter.togglePlayPauseCommand.isEnabled = hasActivePlayer
        commandCenter.skipForwardCommand.isEnabled = canSeekRemotely
        commandCenter.skipBackwardCommand.isEnabled = canSeekRemotely
        commandCenter.changePlaybackPositionCommand.isEnabled = canSeekRemotely
        #endif
    }

    private func tearDownNowPlayingSession() {
        #if os(iOS)
        let commandCenter = MPRemoteCommandCenter.shared()

        remoteCommandTargets.forEach { command, target in
            command.removeTarget(target)
        }
        remoteCommandTargets.removeAll()

        commandCenter.playCommand.isEnabled = false
        commandCenter.pauseCommand.isEnabled = false
        commandCenter.togglePlayPauseCommand.isEnabled = false
        commandCenter.skipForwardCommand.isEnabled = false
        commandCenter.skipBackwardCommand.isEnabled = false
        commandCenter.changePlaybackPositionCommand.isEnabled = false

        clearNowPlayingSession()
        #endif
    }

    private var canSeekRemotely: Bool {
        !isLiveMode && (primaryStreamPlayer?.isSeekable ?? false)
    }

    private var nowPlayingSnapshot: NowPlayingSnapshot {
        NowPlayingSnapshot(
            elapsedTimeSecond: Int(max(currentTime, 0)),
            durationSecond: resolvedDuration.map { Int(max($0, 0)) },
            playbackRate: nowPlayingPlaybackRate,
            wantsPlayback: wantsPlayback,
            isPlaying: isPlaying,
            isBuffering: isBuffering,
            canSeek: canSeekRemotely
        )
    }

    private var nowPlayingPlaybackRate: Double {
        (wantsPlayback && isPlaying && !isBuffering) ? 1 : 0
    }

    private func updateNowPlayingInfoIfNeeded(force: Bool = false) {
        #if os(iOS)
        guard let primaryStreamPlayer else {
            clearNowPlayingSession()
            return
        }

        let snapshot = nowPlayingSnapshot
        guard force || snapshot != lastNowPlayingSnapshot else {
            return
        }

        lastNowPlayingSnapshot = snapshot
        updateRemoteCommandAvailability()

        var nowPlayingInfo = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        nowPlayingInfo[MPMediaItemPropertyTitle] = title
        nowPlayingInfo[MPNowPlayingInfoPropertyMediaType] = MPNowPlayingInfoMediaType.video.rawValue
        nowPlayingInfo[MPNowPlayingInfoPropertyAssetURL] = primaryStreamPlayer.stream.url
        nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = nowPlayingPlaybackRate
        nowPlayingInfo[MPNowPlayingInfoPropertyDefaultPlaybackRate] = 1.0
        nowPlayingInfo[MPNowPlayingInfoPropertyIsLiveStream] = isLiveMode

        if let subtitle, !subtitle.isEmpty {
            nowPlayingInfo[MPMediaItemPropertyArtist] = subtitle
        } else {
            nowPlayingInfo.removeValue(forKey: MPMediaItemPropertyArtist)
        }

        if let resolvedDuration, !isLiveMode {
            nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = resolvedDuration
            if resolvedDuration > 0 {
                nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackProgress] = min(max(currentTime / resolvedDuration, 0), 1)
            } else {
                nowPlayingInfo.removeValue(forKey: MPNowPlayingInfoPropertyPlaybackProgress)
            }
        } else {
            nowPlayingInfo.removeValue(forKey: MPMediaItemPropertyPlaybackDuration)
            nowPlayingInfo.removeValue(forKey: MPNowPlayingInfoPropertyPlaybackProgress)
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
        if #available(iOS 13.0, *) {
            MPNowPlayingInfoCenter.default().playbackState = wantsPlayback ? .playing : .paused
        }
        #endif
    }

    private func clearNowPlayingSession() {
        #if os(iOS)
        lastNowPlayingSnapshot = nil
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        if #available(iOS 13.0, *) {
            MPNowPlayingInfoCenter.default().playbackState = .stopped
        }
        updateRemoteCommandAvailability(isSessionActive: false)
        deactivateAudioSessionIfNeeded()
        #endif
    }

    private func startSharedStateMonitorIfNeeded() {
        guard playsViaAVFoundationOnly,
              streamPlayers.count > 1 else {
            bufferingStreamIDs.removeAll()
            return
        }

        guard sharedStateMonitorTask == nil else {
            return
        }

        sharedStateMonitorTask = Task { [weak self] in
            while !Task.isCancelled {
                await MainActor.run {
                    self?.refreshSharedPlaybackState()
                }
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
        }
    }

    private func stopSharedStateMonitor() {
        sharedStateMonitorTask?.cancel()
        sharedStateMonitorTask = nil
        bufferingStreamIDs.removeAll()
    }

    private func refreshSharedPlaybackState() {
        guard playsViaAVFoundationOnly,
              streamPlayers.count > 1 else {
            bufferingStreamIDs.removeAll()
            syncPrimaryPlaybackStateWithoutSharedBuffering()
            return
        }

        let previouslyBuffered = !bufferingStreamIDs.isEmpty
        bufferingStreamIDs = Set(
            streamPlayers.compactMap { streamPlayer in
                isStreamBuffering(streamPlayer) ? streamPlayer.id : nil
            }
        )

        guard wantsPlayback else {
            syncPrimaryPlaybackStateWithoutSharedBuffering()
            return
        }

        if bufferingStreamIDs.isEmpty {
            if previouslyBuffered, !preservesPlayingStatusWhileScrubbing {
                resumeAllStreamPlayersIfNeeded()
            }

            syncPrimaryPlaybackStateWithoutSharedBuffering()
            return
        }

        if !preservesPlayingStatusWhileScrubbing {
            pauseNonBufferingPeersIfNeeded()
        }

        showsPauseButton = true
        isPlaying = true
        isBuffering = true
    }

    private func syncPrimaryPlaybackStateWithoutSharedBuffering() {
        guard let primaryStreamPlayer else {
            isPlaying = false
            isBuffering = false
            showsPauseButton = false
            return
        }

        if let player = primaryStreamPlayer.avPlayer {
            syncPlaybackState(for: player)
        } else if let player = primaryStreamPlayer.vlcPlayer {
            syncPlaybackState(for: player)
        }
    }

    private func isStreamBuffering(_ streamPlayer: CanvasVideoStreamPlayer) -> Bool {
        switch streamPlayer.kernel {
        case let .avPlayer(player):
            switch player.timeControlStatus {
            case .waitingToPlayAtSpecifiedRate:
                return true
            case .paused:
                return shouldTreatPausedStateAsBuffering(for: player)
            case .playing:
                return false
            @unknown default:
                return false
            }
        case let .vlcPlayer(player):
            if player.isPlaying {
                return false
            }

            switch player.state {
            case .opening, .buffering:
                return true
            case .esAdded, .playing, .paused, .stopped, .ended, .error:
                return false
            @unknown default:
                return false
            }
        }
    }

    private func pauseNonBufferingPeersIfNeeded() {
        for streamPlayer in streamPlayers where !bufferingStreamIDs.contains(streamPlayer.id) {
            guard isStreamActivelyPlaying(streamPlayer) else {
                continue
            }

            streamPlayer.pause()
        }
    }

    private func resumeAllStreamPlayersIfNeeded() {
        for streamPlayer in streamPlayers {
            switch streamPlayer.kernel {
            case let .avPlayer(player):
                if streamPlayers.count == 1, shouldUseImmediateResume(for: player) {
                    player.playImmediately(atRate: 1)
                } else {
                    player.play()
                }
            case let .vlcPlayer(player):
                player.play()
            }
        }
    }

    private func isStreamActivelyPlaying(_ streamPlayer: CanvasVideoStreamPlayer) -> Bool {
        switch streamPlayer.kernel {
        case let .avPlayer(player):
            return player.timeControlStatus == .playing
        case let .vlcPlayer(player):
            return player.isPlaying
        }
    }

    private static func sortedSubtitles(
        _ subtitles: [CanvasVideoTranscriptSegment]
    ) -> [CanvasVideoTranscriptSegment] {
        subtitles
            .filter { $0.text != nil }
            .sorted { lhs, rhs in
                (lhs.bg ?? 0) < (rhs.bg ?? 0)
            }
    }
}

private struct CanvasVideoPlayerSurface: UIViewRepresentable {
    let streamPlayer: CanvasVideoStreamPlayer

    func makeUIView(context: Context) -> CanvasVideoPlayerSurfaceView {
        let view = CanvasVideoPlayerSurfaceView()
        view.bind(to: streamPlayer)
        return view
    }

    func updateUIView(_ uiView: CanvasVideoPlayerSurfaceView, context: Context) {
        uiView.bind(to: streamPlayer)
    }

    static func dismantleUIView(_ uiView: CanvasVideoPlayerSurfaceView, coordinator: ()) {
        uiView.prepareForReuse()
    }
}

private final class CanvasVideoPlayerSurfaceView: UIView {
    let playerLayer = AVPlayerLayer()
    private weak var boundVLCPlayer: VLCMediaPlayer?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        isUserInteractionEnabled = false
        playerLayer.videoGravity = .resizeAspect
        layer.addSublayer(playerLayer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer.frame = bounds
        rebindVLCPlayerIfNeeded()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        rebindVLCPlayerIfNeeded(force: true)
    }

    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        rebindVLCPlayerIfNeeded(force: true)
    }

    func bind(to streamPlayer: CanvasVideoStreamPlayer) {
        switch streamPlayer.kernel {
        case let .avPlayer(player):
            unbindVLCPlayerIfNeeded()

            playerLayer.player = player
            playerLayer.isHidden = false
        case let .vlcPlayer(player):
            playerLayer.player = nil
            playerLayer.isHidden = true

            let isSwitchingPlayers = boundVLCPlayer !== player

            if isSwitchingPlayers {
                unbindVLCPlayerIfNeeded()
                boundVLCPlayer = player
            }

            rebindVLCPlayerIfNeeded(force: true, resetDrawable: isSwitchingPlayers)
        }
    }

    func prepareForReuse() {
        playerLayer.player = nil
        playerLayer.isHidden = false
        unbindVLCPlayerIfNeeded()
    }

    private func unbindVLCPlayerIfNeeded() {
        guard let boundVLCPlayer else {
            return
        }

        if isCurrentDrawableSelf(for: boundVLCPlayer) {
            boundVLCPlayer.drawable = nil
        }

        self.boundVLCPlayer = nil
    }

    private func isCurrentDrawableSelf(for player: VLCMediaPlayer) -> Bool {
        guard let drawable = player.drawable as AnyObject? else {
            return false
        }

        return drawable === self
    }

    private func rebindVLCPlayerIfNeeded(
        force: Bool = false,
        resetDrawable: Bool = false
    ) {
        guard let boundVLCPlayer,
              window != nil,
              bounds.width > 0,
              bounds.height > 0 else {
            return
        }

        if resetDrawable, !isCurrentDrawableSelf(for: boundVLCPlayer) {
            boundVLCPlayer.drawable = nil
        }

        if force || !isCurrentDrawableSelf(for: boundVLCPlayer) {
            boundVLCPlayer.drawable = self
        }
    }
}

enum CanvasVideoOrientationController {
    private static let defaultMask: UIInterfaceOrientationMask = [
        .portrait,
        .portraitUpsideDown
    ]

    private(set) static var currentMask: UIInterfaceOrientationMask = defaultMask

    static func enableVideoPlayerOrientations() {
        setOrientationMask(.allButUpsideDown)
    }

    static func restoreDefaultOrientations() {
        setOrientationMask(defaultMask)
    }

    private static func setOrientationMask(_ mask: UIInterfaceOrientationMask) {
        currentMask = mask

        #if os(iOS)
        guard let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }) else {
            return
        }

        windowScene.keyWindow?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
        windowScene.requestGeometryUpdate(
            .iOS(interfaceOrientations: mask)
        ) { _ in
            // The player still works even if the system keeps the current orientation.
        }
        #endif
    }
}

private extension UIWindowScene {
    var keyWindow: UIWindow? {
        windows.first(where: \.isKeyWindow)
    }
}

private func formatPlaybackSeconds(_ value: Double) -> String {
    let formatter = DateComponentsFormatter()
    let roundedValue = Int(max(value.rounded(), 0))
    formatter.allowedUnits = roundedValue >= 3600 ? [.hour, .minute, .second] : [.minute, .second]
    formatter.zeroFormattingBehavior = [.pad]
    return formatter.string(from: TimeInterval(roundedValue)) ?? "00:00"
}
