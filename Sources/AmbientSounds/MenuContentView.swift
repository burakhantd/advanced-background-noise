import AppKit
import SwiftUI

struct MenuContentView: View {
    @ObservedObject var store: BackgroundSoundsStore
    @StateObject private var mediaController = MediaControllerStore()
    @State private var isManagingCustomSounds = false
    @State private var mediaSeekPosition: TimeInterval = 0
    @State private var isSeekingMedia = false
    @State private var isHoveringMediaSeek = false
    @State private var artworkAccent: ArtworkAccent?
    @State private var artworkFlipDegrees: Double = 0
    @State private var artworkBounceScale: Double = 1.0
    @State private var vinylRotationBaseAngle: Double = 0
    @State private var vinylRotationStartedAt: Date?
    @State private var vinylModeRotationAngle: Double = 0
    @State private var vinylModeTransitionTask: Task<Void, Never>?
    @State private var vinylTransitionScale: CGFloat = 1
    @State private var vinylTransitionOffset: CGFloat = 0
    @State private var vinylTransitionOpacity: Double = 1
    @State private var vinylTransitionBlur: CGFloat = 0
    @State private var vinylNeedleLift: CGFloat = 0
    @State private var vinylTransitionTask: Task<Void, Never>?
    @State private var trackChangeID: UUID = UUID()
    @State private var trackChangeDirection: Int = 1   // +1 = next, -1 = previous
    @State private var displayedArtworkURL: URL? = nil  // updated only at flip midpoint
    @AppStorage("leftMediaSlotAction") private var leftSlotAction: MediaSlotAction = .repeat
    @AppStorage("rightMediaSlotAction") private var rightSlotAction: MediaSlotAction = .shuffle
    @State private var isHoveringLeftSlot = false
    @State private var isHoveringRightSlot = false
    @State private var isQueueHovered = false
    @State private var isShowingQueue = false
    @State private var queueAnimationProgress: CGFloat = 0.0
    @State private var favoriteButtonBounce: Double = 1.0
    @State private var favoriteSuccessGlow: Double = 0.0
   @State private var menuAnimationTrigger = 0
    @State private var lastHandledOpenCount = 0

  var body: some View {
       Group {
            if isManagingCustomSounds {
                CustomSoundManagerView(store: store) {
                    withAnimation(.snappy(duration: 0.22)) {
                        isManagingCustomSounds = false
                    }
                }
                .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                panel
                    .padding(18)
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        .frame(width: 360, alignment: .top)
        .fixedSize(horizontal: false, vertical: true)
       .containerBackground(.clear, for: .window)
       .animation(.snappy(duration: 0.25), value: store.isEnabled)
       .animation(.easeOut(duration: 0.22), value: store.isLayerEnabled)
       .animation(.snappy(duration: 0.2), value: store.isVinylNoiseEnabled)
       .onAppear {
           mediaController.startPolling()
       }
       .onChange(of: store.menuOpenCount) { _, _ in
            handleMenuOpenTrigger()
       }
        .onChange(of: mediaController.item.title) { _, _ in
            if isShowingQueue {
                mediaController.loadQueue()
            }
        }
        .onChange(of: mediaController.item.source) { _, _ in
            if isShowingQueue {
                mediaController.loadQueue()
            }
        }
      .onDisappear { mediaController.stopPolling() }
  }

    private func handleMenuOpenTrigger() {
        guard store.menuOpenCount != lastHandledOpenCount else { return }
        lastHandledOpenCount = store.menuOpenCount
        menuAnimationTrigger += 1
    }

  private var panel: some View {
      VStack(alignment: .leading, spacing: 16) {
          soundAndPlayback
                .menuWaveBounce(index: 0, trigger: menuAnimationTrigger)
          if let error = mediaController.mediaActionError {
              HStack(alignment: .firstTextBaseline, spacing: 8) {
                  Text(error)
                  if mediaController.item.source == .spotify {
                      Button("Settings") {
                          store.openAccessibilitySettings()
                      }
                      .buttonStyle(.link)
                      .font(.caption)
                  }
              }
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          shortcutBar
               .menuWaveBounce(index: 1, trigger: menuAnimationTrigger)
         layerShortcutBar
              .menuWaveBounce(index: 2, trigger: menuAnimationTrigger)
         volumeControl
              .menuWaveBounce(index: 3, trigger: menuAnimationTrigger)
         timerControls
              .menuWaveBounce(index: 4, trigger: menuAnimationTrigger)
         mediaSection
              .menuWaveBounce(index: 5, trigger: menuAnimationTrigger)

         if let error = store.errorMessage {
             Label(error, systemImage: "exclamationmark.triangle.fill")
                 .font(.caption)
                 .foregroundStyle(.orange)
                 .frame(maxWidth: .infinity, alignment: .leading)
                  .menuWaveBounce(index: 6, trigger: menuAnimationTrigger)
         }

     }
      .frame(maxWidth: .infinity, alignment: .leading)
  }

    private var mediaSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            mediaControls

            if isShowingQueue || queueAnimationProgress > 0.001 {
                inlineQueueSection
                    .padding(.top, 12 * queueAnimationProgress)
                    .modifier(AnimatingHeightModifier(height: queueAnimationProgress * queueContentHeight))
                    .opacity(min(1.0, max(0.0, queueAnimationProgress * 1.35)))
                    .clipped()
            }
        }
    }

    private var queueContentHeight: CGFloat {
        if !mediaController.upcomingTracks.isEmpty {
            let rowHeight: CGFloat = 42
            let rowSpacing: CGFloat = 4
            let count = mediaController.upcomingTracks.count
            let contentHeight = CGFloat(count) * rowHeight
                + CGFloat(max(0, count - 1)) * rowSpacing
                + 2
            return min(160, contentHeight)
        }

        return mediaController.isLoadingQueue ? 75 : 96
    }

    private var mediaControls: some View {
        HStack(alignment: .top, spacing: 12) {
            Button(action: mediaController.openSourceApplication) {
                mediaArtwork
            }
            .buttonStyle(.plain)
            .disabled(mediaController.item.source.applicationBundleIdentifier == nil)
            .help(mediaController.item.source.openApplicationLabel)
            .accessibilityLabel(mediaController.item.source.openApplicationLabel)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top, spacing: 6) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(mediaController.item.hasContent ? mediaController.item.title : "Spotify / Apple Music")
                            .font(.callout.weight(.semibold))
                            .lineLimit(1)
                            .id("title-\(trackChangeID)")
                            .transition(.asymmetric(
                                insertion: .move(edge: trackChangeDirection > 0 ? .trailing : .leading)
                                    .combined(with: .opacity),
                                removal: .move(edge: trackChangeDirection > 0 ? .leading : .trailing)
                                    .combined(with: .opacity)
                            ))
                        Text(mediaController.item.hasContent ? mediaController.item.artist : "Nothing is playing")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .id("artist-\(trackChangeID)")
                            .transition(.asymmetric(
                                insertion: .move(edge: trackChangeDirection > 0 ? .trailing : .leading)
                                    .combined(with: .opacity),
                                removal: .move(edge: trackChangeDirection > 0 ? .leading : .trailing)
                                    .combined(with: .opacity)
                            ))
                    }
                    .animation(.spring(response: 0.38, dampingFraction: 0.78), value: trackChangeID)

                    Spacer(minLength: 2)

                    Button(action: store.toggleVinylNoise) {
                        Image(systemName: "record.circle")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(
                                store.isVinylNoiseEnabled
                                    ? AnyShapeStyle(.white)
                                    : AnyShapeStyle(.tertiary)
                            )
                            .frame(width: 24, height: 24)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .glassEffect(
                        store.isVinylNoiseEnabled
                            ? .regular.tint(.brown.opacity(0.72)).interactive()
                            : .clear.interactive(),
                        in: .circle
                    )
                    .accessibilityLabel("Vinyl texture")
                    .accessibilityValue(store.isVinylNoiseEnabled ? "On" : "Off")
                    .help(store.isVinylNoiseEnabled ? "Turn off vinyl texture" : "Add vinyl hiss and crackle")

                    MediaVolumeControl(
                        controller: mediaController,
                        accentColor: mediaAccentColor
                    )
                    .zIndex(10)
                }

                HStack(spacing: 4) {
                    mediaSlotButton(slot: $leftSlotAction, isHovering: $isHoveringLeftSlot)

                    MusicSkipButton(isBackward: true) {
                        trackChangeDirection = -1
                        mediaController.previous()
                    }

                    PlayPauseButton(
                        isPlaying: mediaController.item.isPlaying,
                        action: mediaController.togglePlayback
                    )

                    MusicSkipButton(isBackward: false) {
                        trackChangeDirection = 1
                        mediaController.next()
                    }

                    mediaSlotButton(slot: $rightSlotAction, isHovering: $isHoveringRightSlot)
                }
                .frame(maxWidth: .infinity)
                .disabled(!mediaController.isAvailable || !mediaController.item.hasContent)

                Slider(
                    value: $mediaSeekPosition,
                    in: 0...max(mediaController.item.duration, 1),
                    onEditingChanged: handleMediaSeeking
                )
                    .controlSize(.mini)
                    .tint(isHoveringMediaSeek ? mediaAccentColor : .white)
                    .disabled(!mediaController.item.hasContent || mediaController.item.duration <= 0)
                    .accessibilityLabel("Playback position")
                    .accessibilityValue(mediaTimeLabel(displayedMediaPosition))
                    .onHover { isHoveringMediaSeek = $0 }
                    .animation(.easeOut(duration: 0.16), value: isHoveringMediaSeek)

                HStack {
                    Text(mediaTimeLabel(displayedMediaPosition))
                    Spacer()
                    Text("−\(mediaTimeLabel(max(mediaController.item.duration - displayedMediaPosition, 0)))")
                }
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
            }
        }
        .onAppear {
            syncMediaSeekPosition(with: mediaController.item)
            store.setVinylMusicVolume(mediaController.item.volume)
            displayedArtworkURL = mediaController.item.artworkURL
        }
        .onChange(of: mediaController.item) { old, item in
            syncMediaSeekPosition(with: item)
            store.setVinylMusicVolume(item.volume)
            // Trigger flip + text transition only when switching between two real tracks
            if old.hasContent && (old.title != item.title || old.artist != item.artist) {
                triggerTrackChangeAnimation()
            } else {
                // No track change — update artwork directly (e.g. initial load, volume change)
                displayedArtworkURL = item.artworkURL
            }
        }
        .task(id: mediaController.item.artworkURL) {
            guard let artworkURL = mediaController.item.artworkURL else {
                artworkAccent = nil
                return
            }
            artworkAccent = await ArtworkColorExtractor.accent(from: artworkURL)
        }
    }

    private var mediaArtwork: some View {
        ZStack {
            TimelineView(.animation) { timeline in
                ArtworkImageView(url: displayedArtworkURL) {
                    mediaArtworkPlaceholder
                }
                .frame(width: 86, height: 86)
                .overlay {
                    VinylGroovesOverlay()
                        .opacity(store.isVinylNoiseEnabled ? 1 : 0)
                }
                .clipShape(
                    VinylArtworkShape(
                        cornerRadius: store.isVinylNoiseEnabled ? 43 : 9,
                        holeRadius: store.isVinylNoiseEnabled ? 6.5 : 0
                    ),
                    style: FillStyle(eoFill: true)
                )
                .overlay {
                    Circle()
                        .strokeBorder(Color.primary.opacity(store.isVinylNoiseEnabled ? 0.25 : 0), lineWidth: 0.75)
                        .frame(
                            width: store.isVinylNoiseEnabled ? 13 : 0,
                            height: store.isVinylNoiseEnabled ? 13 : 0
                        )
                        .allowsHitTesting(false)
                }
                .rotationEffect(.degrees(vinylRotationAngle(at: timeline.date)))
                .animation(.easeInOut(duration: 0.48), value: store.isVinylNoiseEnabled)
                .offset(x: store.isVinylNoiseEnabled ? vinylTransitionOffset : 0)
                .scaleEffect(store.isVinylNoiseEnabled ? vinylTransitionScale : 1)
                .opacity(store.isVinylNoiseEnabled ? vinylTransitionOpacity : 1)
                .blur(radius: store.isVinylNoiseEnabled ? vinylTransitionBlur : 0)
            }

            VinylNeedleView(
                isPlaying: mediaController.item.isPlaying,
                isVinyl: store.isVinylNoiseEnabled,
                progress: mediaController.item.progress,
                lift: vinylNeedleLift
            )
            .frame(width: 86, height: 86)
        }
        .frame(width: 86, height: 86)
        // Keep the border stroke independent from the spinning record. It completes
        // a faster 12-second sweep while the record takes 18 seconds.
        .borderStroke(
            borderRadius: store.isVinylNoiseEnabled ? 43 : 9,
            lineWidth: 2.0,
            strength: 0.9,
            duration: 12,
            color: .white,
            trailColor: mediaAccentColor,
            active: mediaController.item.isPlaying
        )
        .animation(.spring(response: 0.34, dampingFraction: 0.78), value: store.isVinylNoiseEnabled)
        // isPlaying scale — independent spring, no coupling with bounce
        .scaleEffect(mediaController.item.isPlaying ? 1.0 : 0.78)
        .animation(.spring(response: 0.48, dampingFraction: 0.82), value: mediaController.item.isPlaying)
        .saturation(mediaController.item.isPlaying ? 1 : 0.08)
        .animation(.spring(response: 0.48, dampingFraction: 0.82), value: mediaController.item.isPlaying)
        .opacity(mediaController.item.isPlaying ? 1 : 0.58)
        .animation(.spring(response: 0.48, dampingFraction: 0.82), value: mediaController.item.isPlaying)
        // Bounce scale — entirely separate layer, won't conflict with isPlaying changes
        .scaleEffect(artworkBounceScale)
        .animation(.spring(response: 0.36, dampingFraction: 0.52), value: artworkBounceScale)
        // Flip rotation on track change
        .rotation3DEffect(
            .degrees(artworkFlipDegrees),
            axis: (x: 0, y: 1, z: 0),
            perspective: 0.4
        )
        .onAppear {
            if store.isVinylNoiseEnabled && mediaController.item.isPlaying {
                vinylRotationStartedAt = Date()
            }
        }
        .onChange(of: mediaController.item.isPlaying) { _, isPlaying in
            if isPlaying && store.isVinylNoiseEnabled {
                vinylRotationStartedAt = Date()
            } else {
                freezeVinylRotation()
            }
        }
        .onChange(of: store.isVinylNoiseEnabled) { _, isEnabled in
            if isEnabled {
                vinylModeTransitionTask?.cancel()
                vinylModeRotationAngle = 0
                vinylRotationBaseAngle = 0
                if mediaController.item.isPlaying {
                    vinylRotationStartedAt = Date()
                }
            } else {
                vinylTransitionTask?.cancel()
                let currentAngle = rawVinylRotationAngle(at: Date())
                let exitTargetAngle = nearestNormalRotation(to: currentAngle)
                vinylRotationStartedAt = nil
                vinylModeTransitionTask?.cancel()
                vinylModeTransitionTask = Task { @MainActor in
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        vinylModeRotationAngle = currentAngle
                    }
                    try? await Task.sleep(for: .milliseconds(16))
                    guard !Task.isCancelled, !store.isVinylNoiseEnabled else { return }
                    withAnimation(.easeInOut(duration: 0.48)) {
                        vinylModeRotationAngle = exitTargetAngle
                    }
                    vinylModeTransitionTask = nil
                }
                withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
                    vinylTransitionScale = 1
                    vinylTransitionOffset = 0
                    vinylTransitionOpacity = 1
                    vinylTransitionBlur = 0
                    vinylNeedleLift = 0
                }
            }
        }
    }

    private func vinylRotationAngle(at date: Date) -> Double {
        guard store.isVinylNoiseEnabled,
              mediaController.item.isPlaying,
              vinylRotationStartedAt != nil else {
            return store.isVinylNoiseEnabled ? vinylRotationBaseAngle : vinylModeRotationAngle
        }

        return rawVinylRotationAngle(at: date)
    }

    private func rawVinylRotationAngle(at date: Date) -> Double {
        guard let start = vinylRotationStartedAt else {
            return vinylRotationBaseAngle
        }

        let elapsed = max(0, date.timeIntervalSince(start))
        let rotation = vinylRotationBaseAngle + elapsed * 20
        return rotation.truncatingRemainder(dividingBy: 360)
    }

    private func nearestNormalRotation(to angle: Double) -> Double {
        [0, 180, 360].min { lhs, rhs in
            abs(lhs - angle) < abs(rhs - angle)
        } ?? 0
    }

    private func freezeVinylRotation() {
        guard let start = vinylRotationStartedAt else { return }
        let elapsed = max(0, Date().timeIntervalSince(start))
        vinylRotationBaseAngle = (vinylRotationBaseAngle + elapsed * 20)
            .truncatingRemainder(dividingBy: 360)
        vinylRotationStartedAt = nil
    }

    private var mediaArtworkPlaceholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: store.isVinylNoiseEnabled ? 43 : 9)
                .fill(.quaternary)
            Image(systemName: "music.note")
                .font(.system(size: 23, weight: .medium))
                .foregroundStyle(.secondary)
                .offset(y: store.isVinylNoiseEnabled ? -14 : 0)
        }
    }

    private func mediaSlotButton(
        slot: Binding<MediaSlotAction>,
        isHovering: Binding<Bool>
    ) -> some View {
        let isFavoriteSlot = slot.wrappedValue == .favorite
        let isPending = isFavoriteSlot && mediaController.isFavoritePending

        return Button(action: {
            performSlotAction(slot.wrappedValue)
        }) {
            ZStack(alignment: .bottom) {
                Image(systemName: slotSymbolName(slot.wrappedValue))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(slotForegroundStyle(slot.wrappedValue, isHovering: isHovering.wrappedValue))
                    .brightness(isHovering.wrappedValue && isSlotActive(slot.wrappedValue) ? 0.22 : 0)
                    .frame(width: 26, height: 26)
                    .symbolEffect(.pulse, isActive: isPending)

                if isSlotActive(slot.wrappedValue) {
                    Circle()
                        .fill(mediaAccentColor)
                        .brightness(isHovering.wrappedValue ? 0.22 : 0)
                        .frame(width: 3, height: 3)
                        .offset(y: -1)
                        .opacity(isPending ? 0.6 : 1.0)
                }
            }
            .scaleEffect((isHovering.wrappedValue ? 1.10 : 1.0) * (isFavoriteSlot ? favoriteButtonBounce : 1.0))
            .opacity(isPending ? 0.85 : 1.0)
            .overlay {
                if isFavoriteSlot && favoriteSuccessGlow > 0 {
                    Circle()
                        .stroke(mediaAccentColor.opacity(favoriteSuccessGlow * 0.9), lineWidth: 1.5)
                        .frame(width: 25, height: 25)
                        .scaleEffect(1.0 + (favoriteSuccessGlow * 0.18))
                        .blur(radius: favoriteSuccessGlow * 0.35)
                }
            }
            .shadow(
                color: isFavoriteSlot ? mediaAccentColor.opacity(favoriteSuccessGlow * 0.75) : .clear,
                radius: favoriteSuccessGlow * 8
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering.wrappedValue = $0 }
        .help(slotHelpText(slot.wrappedValue))
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isHovering.wrappedValue)
        .animation(.snappy(duration: 0.2), value: isSlotActive(slot.wrappedValue))
        .animation(.snappy(duration: 0.2), value: mediaController.item.repeatMode)
        .animation(.easeInOut(duration: 0.3), value: isPending)
        .animation(.easeOut(duration: 0.45), value: favoriteSuccessGlow)
        .onChange(of: mediaController.favoriteConfirmationToken) { _, _ in
            triggerFavoriteSuccessAnimation()
        }
        .contextMenu {
            ForEach(MediaSlotAction.allCases) { action in
                Button {
                    slot.wrappedValue = action
                } label: {
                    if slot.wrappedValue == action {
                        Label(slotMenuTitle(action) + " ✓", systemImage: slotMenuSymbol(action))
                    } else {
                        Label(slotMenuTitle(action), systemImage: slotMenuSymbol(action))
                    }
                }
            }
        }
    }

    private func triggerFavoriteSuccessAnimation() {
        withAnimation(.spring(response: 0.24, dampingFraction: 0.52)) {
            favoriteButtonBounce = 1.16
            favoriteSuccessGlow = 1.0
        }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(120))
            withAnimation(.spring(response: 0.42, dampingFraction: 0.58)) {
                favoriteButtonBounce = 1.0
            }

            try? await Task.sleep(for: .milliseconds(280))
            withAnimation(.easeOut(duration: 0.38)) {
                favoriteSuccessGlow = 0.0
            }
        }
    }

    private func performSlotAction(_ action: MediaSlotAction) {
        switch action {
        case .repeat:
            mediaController.toggleRepeat()
        case .shuffle:
            mediaController.toggleShuffle()
        case .favorite:
            withAnimation(.spring(response: 0.24, dampingFraction: 0.5)) {
                favoriteButtonBounce = 0.82
            }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(110))
                withAnimation(.spring(response: 0.35, dampingFraction: 0.55)) {
                    favoriteButtonBounce = 1.0
                }
            }
            mediaController.toggleFavorite()
        case .queue:
            toggleQueue()
        }
    }

    private func slotSymbolName(_ action: MediaSlotAction) -> String {
        switch action {
        case .repeat:
            return mediaController.item.repeatMode.symbolName
        case .shuffle:
            return "shuffle"
        case .favorite:
            if mediaController.item.source == .music {
                return mediaController.item.isFavorited ? "star.fill" : "star"
            } else {
                return mediaController.item.isFavorited ? "heart.fill" : "heart"
            }
        case .queue:
            return "list.bullet"
        }
    }

    private func isSlotActive(_ action: MediaSlotAction) -> Bool {
        switch action {
        case .repeat:
            return mediaController.item.repeatMode.isActive
        case .shuffle:
            return mediaController.item.isShuffleEnabled
        case .favorite:
            return mediaController.item.isFavorited
        case .queue:
            return isShowingQueue && queueAnimationProgress > 0.05
        }
    }

    private func slotForegroundStyle(_ action: MediaSlotAction, isHovering: Bool) -> Color {
        if isSlotActive(action) {
            return mediaAccentColor
        } else {
            return isHovering ? Color.primary.opacity(0.95) : Color.secondary.opacity(0.6)
        }
    }

    private var repeatHelpText: String {
        switch mediaController.item.repeatMode {
        case .off: return "Repeat: Off"
        case .all: return "Repeat: All"
        case .one: return "Repeat: One Track"
        }
    }

    private func slotHelpText(_ action: MediaSlotAction) -> String {
        switch action {
        case .repeat:
            return repeatHelpText
        case .shuffle:
            return mediaController.item.isShuffleEnabled ? "Shuffle: On" : "Shuffle: Off"
        case .favorite:
            if mediaController.isFavoritePending {
                if mediaController.item.source == .music {
                    return mediaController.item.isFavorited ? "Adding to Favorites…" : "Removing from Favorites…"
                } else {
                    return mediaController.item.isFavorited ? "Adding to Liked Songs…" : "Removing from Liked Songs…"
                }
            }
            if mediaController.item.source == .music {
                return mediaController.item.isFavorited ? "Added to Favorites (Click to remove)" : "Add to Favorites"
            } else {
                return mediaController.item.isFavorited ? "Liked Song (Click to remove)" : "Save to Liked Songs"
            }
        case .queue:
            return isShowingQueue ? "Hide Up Next" : "Show Up Next"
        }
    }

    private func slotMenuTitle(_ action: MediaSlotAction) -> String {
        switch action {
        case .repeat:
            return "Repeat"
        case .shuffle:
            return "Shuffle"
        case .favorite:
            return mediaController.item.source == .music ? "Favorite (Star)" : "Liked Songs (Heart)"
        case .queue:
            return "Up Next / Queue"
        }
    }

    private func slotMenuSymbol(_ action: MediaSlotAction) -> String {
        switch action {
        case .repeat:
            return "repeat"
        case .shuffle:
            return "shuffle"
        case .favorite:
            return mediaController.item.source == .music ? "star" : "heart"
        case .queue:
            return "list.bullet"
        }
    }

    private func toggleQueue() {
        if isShowingQueue && queueAnimationProgress > 0.1 {
            withAnimation(.spring(response: 0.36, dampingFraction: 0.86)) {
                queueAnimationProgress = 0.0
                isQueueHovered = false
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.38) {
                if queueAnimationProgress == 0 {
                    isShowingQueue = false
                }
            }
        } else {
            isShowingQueue = true
            mediaController.loadQueue()
            withAnimation(.spring(response: 0.36, dampingFraction: 0.86)) {
                queueAnimationProgress = 1.0
            }
        }
    }

    private func mediaTimeLabel(_ time: TimeInterval) -> String {
        guard time.isFinite, time > 0 else { return "0:00" }
        let total = Int(time)
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    /// Uses a tonearm-aware record transition for vinyl and the existing flip for artwork.
    private func triggerTrackChangeAnimation() {
        // Update text immediately (drives slide transition)
        trackChangeID = UUID()

        if store.isVinylNoiseEnabled {
            triggerVinylTrackChangeAnimation()
            return
        }

        // Phase 1: rotate to 90° (card goes edge-on — invisible to user)
        let edgeAngle: Double = Double(trackChangeDirection) * 90
        withAnimation(.easeIn(duration: 0.18)) {
            artworkFlipDegrees = edgeAngle
        }

        // Phase 2: while edge-on (invisible), swap the image then open back to 0°
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(185))
            // Card is now edge-on — swap the artwork here so the swap is invisible
            displayedArtworkURL = mediaController.item.artworkURL
            // Instantly jump to the opposite edge (still invisible)
            artworkFlipDegrees = -edgeAngle
            // Animate back to face-forward, revealing the new artwork
            withAnimation(.easeOut(duration: 0.18)) {
                artworkFlipDegrees = 0
            }
            // Bounce: briefly scale up then spring back — fires as card lands face-forward
            try? await Task.sleep(for: .milliseconds(140))
            artworkBounceScale = 1.08
            artworkBounceScale = 1.0   // spring animation takes it home
        }
    }

    private func triggerVinylTrackChangeAnimation() {
        vinylTransitionTask?.cancel()

        withAnimation(.easeOut(duration: 0.16)) {
            vinylNeedleLift = 1
        }
        withAnimation(.easeIn(duration: 0.24)) {
            vinylTransitionScale = 0.72
            vinylTransitionOffset = 0
            vinylTransitionOpacity = 0.28
            vinylTransitionBlur = 4.5
        }

        vinylTransitionTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(245))
            guard !Task.isCancelled else { return }

            displayedArtworkURL = mediaController.item.artworkURL
            vinylRotationBaseAngle = 0
            vinylRotationStartedAt = mediaController.item.isPlaying ? Date() : nil
            vinylTransitionOffset = -86
            vinylTransitionScale = 1.16
            vinylTransitionOpacity = 0.72
            vinylTransitionBlur = 0

            withAnimation(.spring(response: 0.48, dampingFraction: 0.78)) {
                vinylTransitionOffset = 0
                vinylTransitionScale = 1
                vinylTransitionOpacity = 1
            }

            try? await Task.sleep(for: .milliseconds(330))
            guard !Task.isCancelled else { return }

            withAnimation(.spring(response: 0.42, dampingFraction: 0.76)) {
                vinylNeedleLift = 0
            }
            vinylTransitionTask = nil
        }
    }

    private var displayedMediaPosition: TimeInterval {
        isSeekingMedia ? mediaSeekPosition : mediaController.item.elapsedTime
    }

    private var mediaAccentColor: Color {
        guard let artworkAccent else { return .white }
        let readableAccent = artworkAccent.lifted(toMinimumLuminance: 0.42)
        return Color(
            red: readableAccent.red,
            green: readableAccent.green,
            blue: readableAccent.blue
        )
    }

    private func handleMediaSeeking(_ isEditing: Bool) {
        isSeekingMedia = isEditing
        if !isEditing {
            mediaController.seek(to: mediaSeekPosition)
        }
    }

    private func syncMediaSeekPosition(with item: NowPlayingItem) {
        guard !isSeekingMedia else { return }
        mediaSeekPosition = item.clampedPosition(item.elapsedTime)
    }

    private var layerShortcutBar: some View {
        HStack(spacing: 8) {
            ForEach(0..<5, id: \.self) { index in
                let sound = store.layerSound(at: index)
                let isActive = store.isLayerActive(at: index)

                LayerShortcutCapsuleButton(
                    symbol: sound?.symbol ?? "plus",
                    helpText: sound.map { "Second layer: \($0.name) • Right-click to change" } ?? "Add a sound to the second layer",
                    isActive: isActive,
                    action: {
                        store.toggleLayer(at: index)
                    }
                ) {
                    Text("Change second layer")
                    Divider()
                    layerSoundMenuItems(for: index)
                    if sound != nil {
                        Divider()
                        Button("Clear Shortcut", role: .destructive) {
                            store.clearLayerShortcut(at: index)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var shortcutBar: some View {
        HStack(spacing: 8) {
            ForEach(Array(store.shortcuts.enumerated()), id: \.offset) { index, reference in
                let isActive = store.isSelected(reference) && store.isEnabled

                PrimaryShortcutCapsuleButton(
                    symbol: store.symbol(for: reference),
                    title: store.title(for: reference),
                    isActive: isActive,
                    action: {
                        store.activatePrimary(reference)
                    }
                ) {
                    Text("Change shortcut")
                    Divider()
                    ForEach(BackgroundSound.all) { replacement in
                        Button {
                            store.replaceShortcut(at: index, with: .system(replacement.group))
                        } label: {
                            Label(replacement.title, systemImage: replacement.symbol)
                        }
                    }
                    customShortcutMenuItems(for: index)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

   private var soundAndPlayback: some View {
       HStack(spacing: 10) {
           HStack(alignment: .lastTextBaseline, spacing: 5) {
           Menu {
                ForEach(BackgroundSound.all) { sound in
                    Button {
                        store.activatePrimary(.system(sound.group))
                    } label: {
                        Label(
                            sound.title,
                            systemImage: !store.isCustomSelected && sound.group == store.selectedGroup ? "checkmark" : sound.symbol
                        )
                    }
                }

                Divider()

                customSoundMenuItems

                Button(action: store.addCustomSound) {
                    Label("Add Custom Sound…", systemImage: "plus.circle")
                }
            } label: {
                HStack(spacing: 10) {
                    HoverMarqueeText(
                        text: store.selectedTitle,
                        font: .headline,
                        color: .primary,
                        width: 100
                    )

                }
                .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)

                if store.isEnabled, store.isLayerEnabled, let layerSound = store.activeLayerSound {
                    HoverMarqueeText(
                        text: "/ " + layerSound.name,
                        font: .system(size: 9, weight: .semibold),
                        color: Color.secondaryLayerAccent,
                        width: 118
                    )
                }
           }

            if store.timerEnd != nil {
                Text(store.remainingLabel)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            Button {
                withAnimation(.snappy(duration: 0.22)) {
                    isManagingCustomSounds = true
                }
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 32, height: 32)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .glassEffect(.clear.interactive(), in: .circle)
            .help("Manage custom sounds")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .compositingGroup()
    }

    @ViewBuilder
    private func layerSoundMenuItems(for index: Int) -> some View {
        ForEach(store.customFolders) { folder in
            let sounds = store.customSounds(in: folder.id)
            if !sounds.isEmpty {
                Menu(folder.name) {
                    ForEach(sounds) { sound in
                        Button {
                            store.replaceLayerShortcut(at: index, with: sound.id)
                        } label: {
                            Label(sound.name, systemImage: sound.symbol)
                        }
                    }
                }
            }
        }

        let unfiled = store.customSounds(in: nil)
        if !unfiled.isEmpty {
            Menu("Unfiled") {
                ForEach(unfiled) { sound in
                    Button {
                        store.replaceLayerShortcut(at: index, with: sound.id)
                    } label: {
                        Label(sound.name, systemImage: sound.symbol)
                    }
                }
            }
        }

        if store.customSounds.isEmpty {
            Button(action: store.addCustomSound) {
                Label("Add Custom Sound…", systemImage: "plus.circle")
            }
        }
    }


    @ViewBuilder
    private var customSoundMenuItems: some View {
        ForEach(store.customFolders) { folder in
            let sounds = store.customSounds(in: folder.id)
            if !sounds.isEmpty {
                Menu(folder.name) {
                    ForEach(sounds) { sound in
                        customSoundButton(sound)
                    }
                }
            }
        }

        let unfiled = store.customSounds(in: nil)
        if !unfiled.isEmpty {
            Menu("Unfiled") {
                ForEach(unfiled) { sound in
                    customSoundButton(sound)
                }
            }
        }
    }

    @ViewBuilder
    private func customShortcutMenuItems(for index: Int) -> some View {
        if !store.customSounds.isEmpty {
            Divider()
            Text("Custom Sounds")

            ForEach(store.customFolders) { folder in
                let sounds = store.customSounds(in: folder.id)
                if !sounds.isEmpty {
                    Menu(folder.name) {
                        ForEach(sounds) { sound in
                            Button {
                                store.replaceShortcut(at: index, with: .custom(sound.id))
                            } label: {
                                Label(sound.name, systemImage: sound.symbol)
                            }
                        }
                    }
                }
            }

            let unfiled = store.customSounds(in: nil)
            if !unfiled.isEmpty {
                Menu("Unfiled") {
                    ForEach(unfiled) { sound in
                        Button {
                            store.replaceShortcut(at: index, with: .custom(sound.id))
                        } label: {
                            Label(sound.name, systemImage: sound.symbol)
                        }
                    }
                }
            }
        }
    }

    private func customSoundButton(_ sound: CustomSound) -> some View {
        Button {
            store.activatePrimary(.custom(sound.id))
        } label: {
            Label(
                sound.name,
                systemImage: store.selectedCustomID == sound.id ? "checkmark" : sound.symbol
            )
        }
    }

    private var volumeControl: some View {
        VStack(spacing: 8) {
            if store.isLayerEnabled {
                HStack(spacing: 10) {
                    Image(systemName: volumeSymbol(for: store.layerVolume))
                        .foregroundStyle(Color.secondaryLayerAccent)
                        .frame(width: 18)
                        .animation(.easeOut(duration: 0.12), value: store.layerVolume)

                    Slider(
                        value: Binding(
                            get: { store.layerVolume },
                            set: { store.layerVolumeChanged($0) }
                        ),
                        in: 0...1
                    )
                    .tint(Color.secondaryLayerAccent)
                    .help("Layer volume relative to the master")

                    Text("%\(Int(store.layerVolume * 100))")
                        .font(.caption.monospacedDigit().weight(.medium))
                        .foregroundStyle(Color.secondaryLayerAccent)
                        .frame(width: 34, alignment: .trailing)
                }
                .transition(.opacity)
            }

            HStack(spacing: 10) {
                Image(systemName: volumeSymbol(for: store.volume))
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
                    .animation(.easeOut(duration: 0.12), value: store.volume)

                Slider(
                    value: Binding(
                        get: { store.volume },
                        set: { store.volumeChanged($0) }
                    ),
                    in: 0...1,
                    onEditingChanged: store.volumeEditingChanged
                )
                .help("Master volume • controls all layers")

                Text("%\(Int(store.volume * 100))")
                    .font(.caption.monospacedDigit().weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 34, alignment: .trailing)
            }
        }
    }

    private func volumeSymbol(for volume: Double) -> String {
        switch volume {
        case ...0.001: return "speaker.slash.fill"
        case ..<0.5: return "speaker.wave.1.fill"
        default: return "speaker.wave.2.fill"
        }
    }

    private var timerControls: some View {
        TimerControlsSection(store: store)
    }
}

struct MediaVolumeHoverState: Equatable {
    private(set) var isPresented = false
    private(set) var isButtonHovered = false
    private(set) var isPopoverHovered = false
    private(set) var isEditing = false

    mutating func buttonHoverChanged(_ isHovered: Bool) {
        isButtonHovered = isHovered
        if isHovered { isPresented = true }
    }

    mutating func popoverHoverChanged(_ isHovered: Bool) {
        isPopoverHovered = isHovered
        if isHovered { isPresented = true }
    }

    mutating func editingChanged(_ editing: Bool) {
        isEditing = editing
        if editing { isPresented = true }
    }

    mutating func dismissIfIdle() {
        if !isButtonHovered, !isPopoverHovered, !isEditing {
            isPresented = false
        }
    }

    mutating func dismiss() {
        isPresented = false
        isButtonHovered = false
        isPopoverHovered = false
        isEditing = false
    }
}

private struct MediaVolumeControl: View {
    @ObservedObject var controller: MediaControllerStore
    let accentColor: Color
    @State private var hoverState = MediaVolumeHoverState()
    @State private var volumeBeforeMute = 0.7
    @State private var hideTask: Task<Void, Never>?

    var body: some View {
        Button(action: toggleMute) {
            Image(systemName: volumeSymbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(controller.item.volume > 0.001 ? "Mute" : "Unmute")
        .onHover(perform: buttonHoverChanged)
        .popover(
            isPresented: Binding(
                get: { hoverState.isPresented },
                set: { isPresented in
                    if !isPresented { hoverState.dismiss() }
                }
            ),
            arrowEdge: .top
        ) {
            HStack(spacing: 7) {
                Slider(
                    value: Binding(
                        get: { controller.item.volume },
                        set: { controller.setVolume($0) }
                    ),
                    in: 0...1,
                    onEditingChanged: volumeEditingChanged
                )
                .controlSize(.mini)
                .tint(accentColor)
                .frame(width: 96)
                .accessibilityLabel("Music volume")

                Text("%\(Int(controller.item.volume * 100))")
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 26, alignment: .trailing)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .onHover(perform: popoverHoverChanged)
        }
    }

    private var volumeSymbol: String {
        switch controller.item.volume {
        case ...0.001: return "speaker.slash.fill"
        case ..<0.5: return "speaker.wave.1.fill"
        default: return "speaker.wave.2.fill"
        }
    }

    private func toggleMute() {
        if controller.item.volume > 0.001 {
            volumeBeforeMute = controller.item.volume
            controller.setVolume(0)
        } else {
            controller.setVolume(max(volumeBeforeMute, 0.35))
        }
    }

    private func buttonHoverChanged(_ isHovering: Bool) {
        hideTask?.cancel()
        hoverState.buttonHoverChanged(isHovering)
        if !isHovering { scheduleHide() }
    }

    private func popoverHoverChanged(_ isHovering: Bool) {
        hideTask?.cancel()
        hoverState.popoverHoverChanged(isHovering)
        if !isHovering { scheduleHide() }
    }

    private func volumeEditingChanged(_ isEditing: Bool) {
        hoverState.editingChanged(isEditing)
        controller.volumeEditingChanged(isEditing)
        if !isEditing { scheduleHide() }
    }

    private func scheduleHide() {
        hideTask?.cancel()
        hideTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(480))
            guard !Task.isCancelled else { return }
            hoverState.dismissIfIdle()
        }
    }
}

// MARK: - Play / Pause Button

private struct MusicSkipButton: View {
    let isBackward: Bool
    let action: () -> Void

    @State private var id0 = "0-on"
    @State private var id1 = "1-on"
    @State private var animating = 0
    @State private var scale: CGFloat = 1.0
    private let arrowWidth: CGFloat = 10

    var body: some View {
        Button {
            guard animating == 0 else { return }
            animateArrows()
            action()
        } label: {
            HStack(spacing: 0) {
                arrowImage(id: id0)
                    .transition(
                        .asymmetric(
                            insertion: .move(edge: .leading)
                                .combined(with: .scale(scale: 0.5, anchor: .leading)),
                            removal: .scale(scale: 0.0, anchor: .trailing)
                        )
                        .combined(with: .opacity)
                    )

                arrowImage(id: id1)
                    .transition(
                        .asymmetric(
                            insertion: .slide
                                .combined(with: .scale(scale: 0.5, anchor: .leading)),
                            removal: .scale(scale: 0.0, anchor: .trailing)
                        )
                        .combined(with: .opacity)
                    )
            }
            .scaleEffect(x: isBackward ? -1 : 1, y: 1)
            .scaleEffect(scale)
            .frame(width: 36, height: 36)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(isBackward ? "Previous" : "Next")
        .accessibilityLabel(isBackward ? "Previous" : "Next")
        .contentShape(Rectangle())
        .onChange(of: animating) { _, newValue in
            if newValue < 0 {
                animating = 0
            }
        }
    }

    private func animateArrows() {
        withAnimation(.bouncy, completionCriteria: .removed) {
            animating += 1
            id0 = id0 == "0-on" ? "0-off" : "0-on"
            id1 = id1 == "1-on" ? "1-off" : "1-on"
        } completion: {
            animating -= 1
        }

        withAnimation(.easeInOut(duration: 0.1), completionCriteria: .removed) {
            animating += 1
            scale = 0.9
        } completion: {
            withAnimation(.easeInOut(duration: 0.1), completionCriteria: .removed) {
                scale = 1.0
            } completion: {
                animating -= 1
            }
        }
    }

    private func arrowImage(id: String) -> some View {
        Image(systemName: "play.fill")
            .resizable()
            .scaledToFit()
            .frame(width: arrowWidth, height: arrowWidth)
            .id(id)
            .foregroundStyle(.primary)
    }
}

private struct PlayPauseButton: View {
    let isPlaying: Bool
    let action: () -> Void

    @State private var isPressing = false

    var body: some View {
        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
            .font(.system(size: 20, weight: .semibold))
            .frame(width: 34, height: 31)
            .contentTransition(.symbolEffect(.replace.magic(fallback: .downUp)))
            .scaleEffect(isPressing ? 0.82 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.5), value: isPressing)
            .frame(width: 36, height: 36)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !isPressing { isPressing = true }
                    }
                    .onEnded { _ in
                        isPressing = false
                        action()
                    }
            )
            .help(isPlaying ? "Pause" : "Play")
    }
}

// MARK: - App Haptics

private enum AppHaptics {
    static func tap() {
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
    }
}

// MARK: - Primary Shortcut Capsule Button

private struct PrimaryShortcutCapsuleButton<MenuContent: View>: View {
    let symbol: String
    let title: String
    let isActive: Bool
    let action: () -> Void
    @ViewBuilder let contextMenuContent: () -> MenuContent

    @State private var bounceTrigger = 0

    var body: some View {
        Button {
            bounceTrigger += 1
            AppHaptics.tap()
            action()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(isActive ? .white : .primary)
                .frame(maxWidth: .infinity)
                .frame(height: 28)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .glassEffect(
            isActive
                ? .regular.tint(Color.blue.opacity(0.62)).interactive()
                : .clear.interactive(),
            in: .capsule
        )
        .compositingGroup()
        .keyframeAnimator(
            initialValue: TimerAnimationValues(),
            trigger: bounceTrigger
        ) { content, values in
            content
                .overlay {
                    if values.glow > 0.01 {
                        Capsule()
                            .stroke(Color.blue.opacity(values.glow * 0.9), lineWidth: 1.5)
                    }
                }
                .shadow(
                    color: Color.blue.opacity(values.glow * 0.95),
                    radius: 8,
                    x: 0,
                    y: 0
                )
                .scaleEffect(values.scale, anchor: .center)
        } keyframes: { _ in
            KeyframeTrack(\.scale) {
                CubicKeyframe(0.80, duration: 0.09)
                CubicKeyframe(1.10, duration: 0.12)
                CubicKeyframe(0.96, duration: 0.08)
                CubicKeyframe(1.025, duration: 0.07)
                CubicKeyframe(0.985, duration: 0.06)
                CubicKeyframe(1.008, duration: 0.05)
                CubicKeyframe(0.996, duration: 0.04)
                CubicKeyframe(1.000, duration: 0.04)
            }
            KeyframeTrack(\.glow) {
                CubicKeyframe(1.00, duration: 0.09)
                CubicKeyframe(0.65, duration: 0.12)
                CubicKeyframe(0.45, duration: 0.08)
                CubicKeyframe(0.28, duration: 0.07)
                CubicKeyframe(0.16, duration: 0.06)
                CubicKeyframe(0.08, duration: 0.05)
                CubicKeyframe(0.03, duration: 0.04)
                CubicKeyframe(0.00, duration: 0.04)
            }
        }
        .zIndex(isActive ? 2 : (bounceTrigger > 0 ? 1 : 0))
        .contextMenu {
            contextMenuContent()
        }
        .help("\(title) • Click to play/pause • Right-click to change")
    }
}

// MARK: - Layer Shortcut Capsule Button

private struct LayerShortcutCapsuleButton<MenuContent: View>: View {
    let symbol: String
    let helpText: String
    let isActive: Bool
    let action: () -> Void
    @ViewBuilder let contextMenuContent: () -> MenuContent

    @State private var bounceTrigger = 0

    var body: some View {
        Button {
            bounceTrigger += 1
            AppHaptics.tap()
            action()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(
                    isActive
                        ? Color.white
                        : Color.secondaryLayerAccent.opacity(0.72)
                )
                .frame(maxWidth: .infinity)
                .frame(height: 28)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .glassEffect(
            isActive
                ? .regular.tint(Color.secondaryLayerAccent.opacity(0.42)).interactive()
                : .clear.tint(Color.secondaryLayerAccent.opacity(0.035)).interactive(),
            in: .capsule
        )
        .compositingGroup()
        .keyframeAnimator(
            initialValue: TimerAnimationValues(),
            trigger: bounceTrigger
        ) { content, values in
            content
                .overlay {
                    if values.glow > 0.01 {
                        Capsule()
                            .stroke(Color.secondaryLayerAccent.opacity(values.glow * 0.9), lineWidth: 1.5)
                    }
                }
                .shadow(
                    color: Color.secondaryLayerAccent.opacity(values.glow * 0.95),
                    radius: 8,
                    x: 0,
                    y: 0
                )
                .scaleEffect(values.scale, anchor: .center)
        } keyframes: { _ in
            KeyframeTrack(\.scale) {
                CubicKeyframe(0.80, duration: 0.09)
                CubicKeyframe(1.10, duration: 0.12)
                CubicKeyframe(0.96, duration: 0.08)
                CubicKeyframe(1.025, duration: 0.07)
                CubicKeyframe(0.985, duration: 0.06)
                CubicKeyframe(1.008, duration: 0.05)
                CubicKeyframe(0.996, duration: 0.04)
                CubicKeyframe(1.000, duration: 0.04)
            }
            KeyframeTrack(\.glow) {
                CubicKeyframe(1.00, duration: 0.09)
                CubicKeyframe(0.65, duration: 0.12)
                CubicKeyframe(0.45, duration: 0.08)
                CubicKeyframe(0.28, duration: 0.07)
                CubicKeyframe(0.16, duration: 0.06)
                CubicKeyframe(0.08, duration: 0.05)
                CubicKeyframe(0.03, duration: 0.04)
                CubicKeyframe(0.00, duration: 0.04)
            }
        }
        .zIndex(isActive ? 2 : (bounceTrigger > 0 ? 1 : 0))
        .contextMenu {
            contextMenuContent()
        }
        .help(helpText)
    }
}

// MARK: - Timer Capsule Button

private struct TimerRipplePulse: Equatable {
    var token: Int = 0
    var direction: CGFloat = 0
    var isOrigin: Bool = false
    var isDestination: Bool = false
    var peakGlow: CGFloat = 1.0
}

private struct TimerControlsSection: View {
    @ObservedObject var store: BackgroundSoundsStore

    @State private var ripplePulses: [Int: TimerRipplePulse] = [:]
    @State private var departingRawValue: Int? = nil
    @State private var rippleTask: Task<Void, Never>?

    var body: some View {
        HStack(spacing: 5) {
            Button {
                rippleTask?.cancel()
                departingRawValue = nil
                if store.timerEnd != nil { store.cancelTimer() }
            } label: {
                Image(systemName: store.timerEnd == nil ? "timer" : "xmark.circle.fill")
                    .foregroundStyle(store.timerEnd == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.red))
                    .frame(width: 18, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(store.timerEnd == nil)
            .help(store.timerEnd == nil ? "Sleep timer" : "Cancel timer")

            ForEach(TimerPreset.allCases) { preset in
                let isCurrentActive = (store.activeTimerMinutes == preset.rawValue) && (departingRawValue != preset.rawValue)
                TimerCapsuleButton(
                    preset: preset,
                    isActive: isCurrentActive,
                    isDeparting: departingRawValue == preset.rawValue,
                    pulse: ripplePulses[preset.rawValue] ?? TimerRipplePulse()
                ) {
                    handleTap(preset)
                }
            }
        }
    }

    private func handleTap(_ targetPreset: TimerPreset) {
        let presets = TimerPreset.allCases
        guard let targetIdx = presets.firstIndex(of: targetPreset) else { return }
        let currentIdx = presets.firstIndex(where: { $0.rawValue == store.activeTimerMinutes })

        rippleTask?.cancel()

        guard let currentIdx, currentIdx != targetIdx else {
            departingRawValue = nil
            var pulse = ripplePulses[targetPreset.rawValue, default: .init()]
            pulse.token += 1
            pulse.direction = 0
            pulse.isOrigin = false
            pulse.isDestination = true
            pulse.peakGlow = 1.0
            ripplePulses[targetPreset.rawValue] = pulse
            store.startTimer(minutes: targetPreset.rawValue)
            return
        }

        let originPreset = presets[currentIdx]
        departingRawValue = originPreset.rawValue

        let stepCount = abs(targetIdx - currentIdx)
        let totalDistance = max(CGFloat(stepCount), 1.0)
        let step = targetIdx > currentIdx ? 1 : -1
        let direction: CGFloat = targetIdx > currentIdx ? 1.0 : -1.0
        let path = Array(stride(from: currentIdx, through: targetIdx, by: step))

        rippleTask = Task { @MainActor in
            for (stepIndex, idx) in path.enumerated() {
                guard !Task.isCancelled else { return }
                let isFirst = (stepIndex == 0)
                let isLast = (idx == targetIdx)
                let p = presets[idx]

                let progress = CGFloat(stepIndex) / totalDistance
                let stepGlow = 0.60 + progress * 0.40

                var pulse = ripplePulses[p.rawValue, default: .init()]
                pulse.token += 1
                pulse.direction = direction
                pulse.isOrigin = isFirst
                pulse.isDestination = isLast
                pulse.peakGlow = isLast ? 1.0 : stepGlow
                ripplePulses[p.rawValue] = pulse

                if isLast {
                    departingRawValue = nil
                    store.startTimer(minutes: targetPreset.rawValue)
                } else {
                    try? await Task.sleep(for: .milliseconds(95))
                }
            }
        }
    }
}

private struct TimerAnimationValues {
    var scale: CGFloat = 1.0
    var glow: CGFloat = 0.0
}

private struct TimerCapsuleButton: View {
    let preset: TimerPreset
    let isActive: Bool
    let isDeparting: Bool
    let pulse: TimerRipplePulse
    let action: () -> Void

    @State private var bounceTrigger = 0
    @State private var sparkOffset: CGFloat = 0
    @State private var sparkScale: CGFloat = 1.0
    @State private var sparkGlow: CGFloat = 0.0
    @State private var originFade: CGFloat = 0.0

    var body: some View {
        Button(action: {
            AppHaptics.tap()
            action()
        }) {
            Text(preset.label)
                .font(.caption2.weight(.medium))
                .foregroundStyle((isActive || sparkGlow > 0.25 || (isDeparting && originFade > 0.25)) ? .white : .secondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .frame(height: 26)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .glassEffect(
            isActive
                ? .regular.tint(preset.accentColor.opacity(0.68)).interactive()
                : .clear.interactive(),
            in: .capsule
        )
        .overlay {
            let activeGlow = max(sparkGlow, isDeparting ? originFade : 0.0)
            if activeGlow > 0.01 {
                Capsule()
                    .fill(preset.accentColor.opacity(activeGlow * 0.42))
                Capsule()
                    .stroke(preset.accentColor.opacity(activeGlow * 0.85), lineWidth: 1.5)
            }
        }
        .shadow(
            color: preset.accentColor.opacity(max(sparkGlow, isDeparting ? originFade : 0.0) * 0.95),
            radius: 8,
            x: 0,
            y: 0
        )
        .scaleEffect(sparkScale, anchor: .center)
        .offset(x: sparkOffset)
        .compositingGroup()
        .keyframeAnimator(
            initialValue: TimerAnimationValues(),
            trigger: bounceTrigger
        ) { content, values in
            content
                .overlay {
                    if values.glow > 0.01 {
                        Capsule()
                            .fill(preset.accentColor.opacity(values.glow * 0.42))
                        Capsule()
                            .stroke(preset.accentColor.opacity(values.glow * 0.85), lineWidth: 1.5)
                    }
                }
                .shadow(
                    color: preset.accentColor.opacity(values.glow * 0.95),
                    radius: 8,
                    x: 0,
                    y: 0
                )
                .scaleEffect(values.scale, anchor: .center)
        } keyframes: { _ in
            KeyframeTrack(\.scale) {
                CubicKeyframe(0.80, duration: 0.13)
                CubicKeyframe(1.10, duration: 0.18)
                CubicKeyframe(0.96, duration: 0.12)
                CubicKeyframe(1.025, duration: 0.10)
                CubicKeyframe(0.985, duration: 0.08)
                CubicKeyframe(1.008, duration: 0.07)
                CubicKeyframe(0.996, duration: 0.06)
                CubicKeyframe(1.000, duration: 0.06)
            }
            KeyframeTrack(\.glow) {
                CubicKeyframe(1.00, duration: 0.13)
                CubicKeyframe(0.65, duration: 0.18)
                CubicKeyframe(0.45, duration: 0.12)
                CubicKeyframe(0.28, duration: 0.10)
                CubicKeyframe(0.16, duration: 0.08)
                CubicKeyframe(0.08, duration: 0.07)
                CubicKeyframe(0.03, duration: 0.06)
                CubicKeyframe(0.00, duration: 0.06)
            }
        }
        .zIndex(isActive ? 2 : (sparkGlow > 0.1 ? 1 : 0))
        .help("\(preset.label) start timer")
        .onChange(of: pulse.token) { _, _ in
            handlePulse()
        }
    }

    private func handlePulse() {
        if pulse.isDestination {
            bounceTrigger += 1
            if pulse.direction != 0 {
                sparkOffset = pulse.direction * 5.5
                withAnimation(.spring(response: 0.48, dampingFraction: 0.60)) {
                    sparkOffset = 0
                }
            }
        } else if pulse.isOrigin {
            originFade = pulse.peakGlow
            sparkOffset = pulse.direction * 6.5
            sparkScale = 0.82
            withAnimation(.easeOut(duration: 0.42)) {
                originFade = 0
            }
            withAnimation(.spring(response: 0.44, dampingFraction: 0.62)) {
                sparkOffset = 0
                sparkScale = 1.0
            }
        } else {
            sparkOffset = pulse.direction * 6.5
            sparkScale = 0.82
            sparkGlow = pulse.peakGlow
            withAnimation(.spring(response: 0.44, dampingFraction: 0.58)) {
                sparkOffset = 0
                sparkScale = 1.0
                sparkGlow = 0
            }
        }
    }
}

// MARK: - Inline Queue Section

extension MenuContentView {
    private var inlineQueueSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if mediaController.isLoadingQueue && mediaController.upcomingTracks.isEmpty {
                HStack {
                    Spacer()
                    ProgressView()
                        .scaleEffect(0.8)
                    Spacer()
                }
                .frame(height: 75)
            } else if !mediaController.upcomingTracks.isEmpty {
                ScrollView(.vertical, showsIndicators: isQueueHovered) {
                    VStack(spacing: 4) {
                        ForEach(Array(mediaController.upcomingTracks.enumerated()), id: \.element.id) { index, track in
                            HStack(spacing: 8) {
                                Text("\(index + 1)")
                                    .font(.system(size: 10, weight: .semibold).monospacedDigit())
                                    .foregroundStyle(.tertiary)
                                    .frame(width: 16, alignment: .trailing)

                                ArtworkImageView(url: track.artworkURL) {
                                    queueArtworkPlaceholder
                                }
                                .frame(width: 32, height: 32)
                                .clipShape(RoundedRectangle(cornerRadius: 6))

                                VStack(alignment: .leading, spacing: 1) {
                                    Text(track.title)
                                        .font(.caption.weight(.medium))
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                    Text(track.artist)
                                        .font(.system(size: 10))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }

                                Spacer(minLength: 4)

                                if !track.duration.isEmpty {
                                    Text(track.duration)
                                        .font(.system(size: 10).monospacedDigit())
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            .padding(.vertical, 5)
                            .padding(.horizontal, 8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 6))
                        }
                    }
                    .padding(.vertical, 1)
                }
                .frame(height: queueContentHeight)
                .controlSize(.mini)
                .onHover { isQueueHovered = $0 }
                .background(ScrollViewStyleConfigurator())
            } else {
                VStack(spacing: 6) {
                    Image(systemName: "music.note.list")
                        .font(.system(size: 18))
                        .foregroundStyle(.secondary.opacity(0.5))
                    if mediaController.item.source == .spotify {
                        Text("Could not read the queue. Make sure Spotify is open and Accessibility access is enabled.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 8)
                        Button {
                            mediaController.openSpotifyQueue()
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "list.bullet")
                                Text("Open Spotify Queue")
                            }
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(.quaternary, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 2)
                    } else {
                        Text("There are no more songs in the queue")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
        }
    }

    private var queueArtworkPlaceholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(.quaternary)
            Image(systemName: "music.note")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }
}

struct AnimatingHeightModifier: AnimatableModifier {
    var height: CGFloat

    var animatableData: CGFloat {
        get { height }
        set { height = newValue }
    }

    func body(content: Content) -> some View {
        content
            .frame(height: max(0, height), alignment: .top)
            .clipped()
    }
}

private struct ScrollViewStyleConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        NSView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        install(on: nsView, attempt: 0)
    }

    private func install(on nsView: NSView, attempt: Int) {
        DispatchQueue.main.async {
            var scrollViews: [NSScrollView] = []
            if let enclosing = nsView.enclosingScrollView {
                scrollViews = [enclosing]
            } else if let window = nsView.window, let contentView = window.contentView {
                scrollViews = self.findScrollViews(in: contentView)
            } else {
                scrollViews = self.findScrollViews(from: nsView)
            }

            if !scrollViews.isEmpty {
                for scrollView in scrollViews {
                    scrollView.scrollerStyle = .overlay
                    scrollView.autohidesScrollers = true
                    if !(scrollView.verticalScroller is ThinQueueScroller) {
                        let scroller = ThinQueueScroller()
                        scroller.scrollerStyle = .overlay
                        scroller.controlSize = .mini
                        scrollView.verticalScroller = scroller
                    }
                }
                return
            }

            // SwiftUI may attach the representable before the NSScrollView
            // exists. Retry after layout so the native thick scroller cannot
            // win the race.
            guard attempt < 40 else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) {
                self.install(on: nsView, attempt: attempt + 1)
            }
        }
    }

    private func findScrollViews(from nsView: NSView) -> [NSScrollView] {
        var view: NSView? = nsView
        while let current = view {
            if let scrollView = current as? NSScrollView {
                return [scrollView]
            }
            view = current.superview
        }
        return []
    }

    private func findScrollViews(in view: NSView) -> [NSScrollView] {
        var result: [NSScrollView] = []
        if let scrollView = view as? NSScrollView {
            result.append(scrollView)
        }
        for child in view.subviews {
            result.append(contentsOf: findScrollViews(in: child))
        }
        return result
    }
}

private final class ThinQueueScroller: NSScroller {
    override func drawKnobSlot(in slotRect: NSRect, highlight: Bool) {
        // Keep the overlay track invisible; only the thumb appears while the
        // SwiftUI ScrollView reports that the pointer is over the queue.
    }

    override func drawKnob() {
        let knobRect = rect(for: .knob)
        guard knobRect.height > 1 else { return }

        let width: CGFloat = 0.5
        let thinRect = NSRect(
            x: bounds.midX - width / 2,
            y: knobRect.minY,
            width: width,
            height: knobRect.height
        )
        NSColor.white.withAlphaComponent(0.52).setFill()
        NSBezierPath(roundedRect: thinRect, xRadius: width / 2, yRadius: width / 2).fill()
    }
}

struct ArtworkImageView<Placeholder: View>: View {
    let url: URL?
    let placeholder: () -> Placeholder

    var body: some View {
        if let url {
            if url.isFileURL, let nsImage = NSImage(contentsOf: url) {
                Image(nsImage: nsImage)
                    .resizable()
                    .scaledToFill()
            } else {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .scaledToFill()
                    } else {
                        placeholder()
                    }
                }
            }
        } else {
            placeholder()
        }
    }
}

// MARK: - Vinyl Artwork Components

struct VinylArtworkShape: Shape {
    var cornerRadius: CGFloat
    var holeRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(cornerRadius, holeRadius) }
        set {
            cornerRadius = newValue.first
            holeRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let outer = Path(roundedRect: rect, cornerRadius: cornerRadius)
        path.addPath(outer)

        if holeRadius > 0.1 {
            let center = CGPoint(x: rect.midX, y: rect.midY)
            let holeRect = CGRect(
                x: center.x - holeRadius,
                y: center.y - holeRadius,
                width: holeRadius * 2,
                height: holeRadius * 2
            )
            path.addPath(Path(ellipseIn: holeRect))
        }

        return path
    }
}

struct VinylGroovesOverlay: View {
    var body: some View {
        ZStack {
            // Concentric vinyl run grooves (subtle texture)
            Circle()
                .stroke(Color.black.opacity(0.08), lineWidth: 0.5)
                .frame(width: 74, height: 74)
            Circle()
                .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
                .frame(width: 62, height: 62)
            Circle()
                .stroke(Color.black.opacity(0.08), lineWidth: 0.5)
                .frame(width: 50, height: 50)
            Circle()
                .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
                .frame(width: 38, height: 38)
            Circle()
                .stroke(Color.black.opacity(0.12), lineWidth: 0.75)
                .frame(width: 26, height: 26)

            // Subtle vinyl sheen reflection
            AngularGradient(
                stops: [
                    .init(color: .clear, location: 0.0),
                    .init(color: .white.opacity(0.07), location: 0.22),
                    .init(color: .clear, location: 0.30),
                    .init(color: .clear, location: 0.5),
                    .init(color: .white.opacity(0.07), location: 0.72),
                    .init(color: .clear, location: 0.80),
                    .init(color: .clear, location: 1.0)
                ],
                center: .center
            )
            .blendMode(.screen)
        }
        .allowsHitTesting(false)
    }
}

struct TonearmArmPath: Shape {
    let pivot: CGPoint
    var stylus: CGPoint

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(stylus.x, stylus.y) }
        set {
            stylus.x = newValue.first
            stylus.y = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: pivot)
        let elbow = CGPoint(
            x: pivot.x + (stylus.x - pivot.x) * 0.52 + 3,
            y: pivot.y + (stylus.y - pivot.y) * 0.52
        )
        path.addLine(to: elbow)
        path.addLine(to: stylus)
        return path
    }
}

struct VinylNeedleView: View {
    let isPlaying: Bool
    let isVinyl: Bool
    let progress: Double
    let lift: CGFloat

    private var armAngle: Double {
        if !isVinyl {
            return 32
        } else if isPlaying {
            return Double(lift * 24)
        } else {
            return 18 + Double(lift * 12)
        }
    }

    var body: some View {
        GeometryReader { _ in
            let pivot = CGPoint(x: 8, y: 10)
            let recordCenter = CGPoint(x: 43, y: 43)
            let clampedProgress = min(max(progress, 0), 1)
            // A real stylus travels from the outer groove toward the label as
            // the track advances. Keep the travel on the lower-left groove arc.
            let grooveRadius = 35 - (clampedProgress * 21)
            let grooveAngle = 2.35
            let stylus = CGPoint(
                x: recordCenter.x + cos(grooveAngle) * grooveRadius,
                y: recordCenter.y + sin(grooveAngle) * grooveRadius
            )

            ZStack(alignment: .topLeading) {
                // Drop shadow
                TonearmArmPath(pivot: pivot, stylus: stylus)
                    .stroke(Color.black.opacity(0.45), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                    .offset(x: 1.5, y: 2)

                // Metallic arm
                TonearmArmPath(pivot: pivot, stylus: stylus)
                    .stroke(
                        LinearGradient(
                            colors: [Color(white: 0.95), Color(white: 0.70), Color(white: 0.85)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        style: StrokeStyle(lineWidth: 2.0, lineCap: .round, lineJoin: .round)
                    )

                // Cartridge / Headshell
                let headPoint = stylus
                ZStack {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(LinearGradient(colors: [Color(white: 0.25), Color(white: 0.15)], startPoint: .leading, endPoint: .trailing))
                        .frame(width: 5, height: 9)
                        .overlay(RoundedRectangle(cornerRadius: 1).stroke(Color.white.opacity(0.3), lineWidth: 0.5))
                        .rotationEffect(.degrees(-35))
                        .position(headPoint)

                    Circle()
                        .fill(Color(red: 1.0, green: 0.45, blue: 0.2))
                        .frame(width: 2, height: 2)
                        .position(x: headPoint.x + 2.5, y: headPoint.y + 3.5)
                }

                // Counterweight behind pivot
                Circle()
                    .fill(RadialGradient(colors: [Color(white: 0.5), Color(white: 0.2)], center: .center, startRadius: 1, endRadius: 6))
                    .frame(width: 8, height: 8)
                    .overlay(Circle().stroke(Color(white: 0.7).opacity(0.4), lineWidth: 0.5))
                    .position(x: pivot.x - 3.5, y: pivot.y - 3.5)

                // Pivot gimbal
                Circle()
                    .fill(LinearGradient(colors: [Color(white: 0.85), Color(white: 0.4)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 8, height: 8)
                    .overlay(Circle().stroke(Color.black.opacity(0.5), lineWidth: 0.5))
                    .position(pivot)

                // Center screw
                Circle()
                    .fill(Color(white: 0.2))
                    .frame(width: 2.5, height: 2.5)
                    .position(pivot)
            }
            .rotationEffect(.degrees(armAngle), anchor: UnitPoint(x: pivot.x / 86.0, y: pivot.y / 86.0))
            .animation(.spring(response: 0.45, dampingFraction: 0.75), value: armAngle)
            .animation(.easeInOut(duration: 0.52), value: progress)
            .opacity(isVinyl ? 1 : 0)
            .offset(x: isVinyl ? 0 : -16, y: isVinyl ? 0 : -8)
            .animation(.spring(response: 0.42, dampingFraction: 0.75), value: isVinyl)
        }
        .allowsHitTesting(false)
    }
}



// MARK: - Menu Wave Bounce Modifier

private struct SmoothWaveModifier: AnimatableModifier {
    var progress: CGFloat = 0.0
    var anchor: UnitPoint = .top

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        let cycle = progress.truncatingRemainder(dividingBy: 1.0)
        let t = (cycle == 0 && progress > 0) ? 1.0 : cycle

        // A broad primary crest followed by a very soft, signed tail. Keeping
        // the tail signed avoids stacking several sharp positive crests, which
        // is what made the title look like it was twitching.
        let damping = pow(max(0.0, 1.0 - t), 1.8)
        let wave = sin(1.75 * .pi * t) * damping
        let scale = 1.0 + (0.026 * wave)
        let yOffset = 2.0 * wave

        return content
            .scaleEffect(scale, anchor: anchor)
            .offset(y: yOffset)
    }
}

private struct MenuWaveBounceModifier: ViewModifier {
    let index: Int
    let trigger: Int
    var anchor: UnitPoint = .center
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var waveProgress: CGFloat = 0.0

    func body(content: Content) -> some View {
        content
            .compositingGroup()
            .modifier(SmoothWaveModifier(progress: waveProgress, anchor: anchor))
            .onChange(of: trigger) { _, _ in
                guard !reduceMotion else { return }
                runBounce()
            }
    }

    private func runBounce() {
        // 30 fps timeline: 2 frames (66.7ms) per segment step (0, 2, 4, 6, 8, 10, 12)
        let delay = Double(index) * (2.0 / 30.0)
        withAnimation(.linear(duration: 0.72).delay(delay)) {
            waveProgress += 1.0
        }
    }
}

private extension View {
    func menuWaveBounce(index: Int, trigger: Int, anchor: UnitPoint = .center) -> some View {
        modifier(MenuWaveBounceModifier(index: index, trigger: trigger, anchor: anchor))
    }
}

private struct HoverMarqueeText: View {
    let text: String
    let font: Font
    let color: Color
    let width: CGFloat

    @State private var isHovered = false
    @State private var textWidth: CGFloat = 0

    var body: some View {
        GeometryReader { proxy in
            Text(text)
                .font(font)
                .foregroundStyle(color)
                .fixedSize(horizontal: true, vertical: false)
                .background {
                    GeometryReader { textProxy in
                        Color.clear
                            .onAppear { textWidth = textProxy.size.width }
                            .onChange(of: textProxy.size.width) { _, newWidth in
                                textWidth = newWidth
                            }
                    }
                }
                .offset(x: isHovered ? min(0, proxy.size.width - textWidth) : 0)
                .animation(.easeInOut(duration: 1.0), value: isHovered)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .clipped()
                .onHover { isHovered = $0 }
        }
        .frame(width: width, height: 20, alignment: .bottom)
        .alignmentGuide(.lastTextBaseline) { dimensions in
            dimensions[.bottom]
        }
        .clipped()
    }
}
