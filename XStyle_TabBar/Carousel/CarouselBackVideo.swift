import AVFoundation
import CoreImage
import CoreVideo
import SwiftUI
import UIKit

/// Where a card's back plays its video (`CardCarousel.cardBackVideo`). Put it in the
/// `cardBack` view where the video belongs and size it like any view. On 3D cards Metal
/// prints the video there, on the paper's back under the plastic; on flat cards a player
/// view fills it. It is empty in a back without a video.
public struct CarouselBackVideo: View {
    private let cornerRadius: CGFloat
    private let normalizedCrop: CGRect?
    @Environment(\.carouselBackVideo) private var context

    public init(cornerRadius: CGFloat = 14, normalizedCrop: CGRect? = nil) {
        self.cornerRadius = cornerRadius
        self.normalizedCrop = normalizedCrop
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .circular)
        switch context {
        case .printed(let recorder):
            // A printed back only notes where the panel lies; Metal draws the video there.
            GeometryReader { proxy in
                let _ = recorder.record(proxy.frame(in: .named(CarouselBackVideoContext.space)),
                                        cornerRadius: cornerRadius)
                shape.fill(Color.black.opacity(0.12))
            }
        case .hosted(let playback, let index):
            ZStack {
                shape.fill(Color.black.opacity(0.12))
                CarouselBackVideoLayer(playback: playback, index: index, normalizedCrop: normalizedCrop)
                    .clipShape(shape)
            }
        case nil:
            Color.clear
        }
    }
}

/// How a back's `CarouselBackVideo` shows its video.
enum CarouselBackVideoContext {
    /// The coordinate space of a back view printed on a 3D card.
    static let space = "carousel.back"
    /// The back is a still printed by Metal: the panel records its place.
    case printed(CarouselBackVideoRecorder)
    /// The back is a live view (flat cards): the panel shows the player when it plays `index`.
    case hosted(CarouselBackVideoPlayback, index: Int)
}

private struct CarouselBackVideoKey: EnvironmentKey {
    static let defaultValue: CarouselBackVideoContext? = nil
}

extension EnvironmentValues {
    var carouselBackVideo: CarouselBackVideoContext? {
        get { self[CarouselBackVideoKey.self] }
        set { self[CarouselBackVideoKey.self] = newValue }
    }
}

/// Where a printed back's video panel lies, in the back view's points.
final class CarouselBackVideoRecorder {
    private(set) var frame: CGRect?
    private(set) var cornerRadius: CGFloat = 0

    func record(_ frame: CGRect, cornerRadius: CGFloat) {
        self.frame = frame
        self.cornerRadius = cornerRadius
    }
}

/// A flat card's video panel: a still of its video (its first frame, or the frame it
/// stopped on) under an `AVPlayerLayer` on the shared player, shown once it plays this card.
private struct CarouselBackVideoLayer: UIViewRepresentable {
    let playback: CarouselBackVideoPlayback
    let index: Int
    let normalizedCrop: CGRect?

    func makeUIView(context: Context) -> CarouselPlayerView {
        let view = CarouselPlayerView()
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: CarouselPlayerView, context: Context) {
        view.normalizedCrop = normalizedCrop
        playback.attach(view, index: index)
    }
}

final class CarouselPlayerView: UIView {
    private let stillLayer = CALayer()
    private let playerLayer = AVPlayerLayer()
    var normalizedCrop: CGRect? {
        didSet { if normalizedCrop != oldValue { setNeedsLayout() } }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        stillLayer.contentsGravity = .resizeAspectFill
        stillLayer.masksToBounds = true
        playerLayer.videoGravity = .resizeAspectFill
        playerLayer.isHidden = true
        layer.addSublayer(stillLayer)
        layer.addSublayer(playerLayer)
    }

    required init?(coder: NSCoder) { nil }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if let crop = normalizedCrop, crop.minX.isFinite, crop.minY.isFinite,
           crop.width.isFinite, crop.height.isFinite, crop.width > 0, crop.height > 0 {
            let source = CGRect(x: -crop.minX * bounds.width / crop.width,
                                y: -crop.minY * bounds.height / crop.height,
                                width: bounds.width / crop.width, height: bounds.height / crop.height)
            stillLayer.contentsGravity = .resize
            playerLayer.videoGravity = .resize
            stillLayer.frame = source
            playerLayer.frame = source
        } else {
            stillLayer.contentsGravity = .resizeAspectFill
            playerLayer.videoGravity = .resizeAspectFill
            stillLayer.frame = bounds
            playerLayer.frame = bounds
        }
        CATransaction.commit()
    }

    /// `player` once it shows this card's frames, over `still` (never an empty, black layer).
    func show(player: AVPlayer?, still: CGImage?) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if let still { stillLayer.contents = still }
        if playerLayer.player !== player { playerLayer.player = player }
        playerLayer.isHidden = player == nil
        CATransaction.commit()
    }
}

/// The one player of a carousel's back videos, after the onboarding's wheel: muted, looping
/// without a gap (`AVPlayerLooper`), restarted from its first frame each time a card is
/// selected, each asset loaded once. Metal reads its frames from a video output on each
/// looping item; flat cards' panels show it through an `AVPlayerLayer`. Every other card
/// showing its back holds a still of its own video: its first frame (`poster`, drawn once
/// per file) until it has played, then the frame it stopped on, so no panel is ever empty.
@MainActor
final class CarouselBackVideoPlayback {
    struct RetainedPosition {
        let url: URL
        let time: CMTime
        let frame: CVPixelBuffer?
    }

    struct Snapshot {
        let index: Int?
        let isPlaying: Bool
        let player: ObjectIdentifier
        let session: UInt64?
        let time: Double
        let isRestoringPosition: Bool
    }

    /// Immutable diagnostics never retain a player item or its decoded frames.
    var snapshot: Snapshot {
        Snapshot(index: index, isPlaying: isPlaying, player: ObjectIdentifier(player),
                 session: looper == nil ? nil : playbackSession, time: player.currentTime().seconds,
                 isRestoringPosition: resumeTime != nil && !resumeFailed)
    }

    let player = AVQueuePlayer()
    private var looper: AVPlayerLooper?
    private var playbackSession: UInt64 = 0
    private var loadGeneration: UInt64 = 0
    private var preservesPosition = false
    private var positions: [Int: (url: URL, time: CMTime)] = [:]
    private var resumeTime: CMTime?
    private var resumeSeeking = false
    private var resumeFailed = false
    private var resumeQueueObservation: NSKeyValueObservation?
    private var resumeItemObservation: NSKeyValueObservation?
    private weak var resumeObservedItem: AVPlayerItem?
    private var pendingStillFrame: CVPixelBuffer?
    private let assetStore: CarouselVideoAssetStore
    private var outputs: [ObjectIdentifier: AVPlayerItemVideoOutput] = [:]
    private var views: [(index: Int, view: WeakPlayerView)] = []
    private var posters: [URL: CGImage] = [:]
    private var posterLoads: Set<URL> = []
    private var urls: [Int: URL] = [:]
    private var lastFrames: [Int: CVPixelBuffer] = [:]
    private lazy var images = CIContext()
    /// The card whose video is loaded, and whether it plays.
    private(set) var index: Int?
    private(set) var isPlaying = false
    /// Whether the loaded video has delivered a frame yet.
    private(set) var hasFrame = false
    /// The loaded video's frame rate, for the display link.
    private(set) var frameRate: Float = 30
    private var hasVideoTrack = true
    /// Called when a poster is ready, so a printed back can show it.
    var onPoster: (() -> Void)?
    private var url: URL?

    init(assetStore: CarouselVideoAssetStore? = nil) {
        self.assetStore = assetStore ?? CarouselVideoAssetStore()
        player.isMuted = true
        player.preventsDisplaySleepDuringVideoPlayback = false
        player.automaticallyWaitsToMinimizeStalling = false
    }

    /// Card `index` shows its back with this video: its poster starts loading.
    func register(_ url: URL, for index: Int) {
        guard urls[index] != url else { return }
        urls[index] = url
        lastFrames[index] = nil
        positions[index] = nil
        _ = poster(for: url)
        refreshViews()
    }

    /// Legacy backs start at the beginning. Features opt into retaining their own
    /// playheads and last frames across nearest-card changes. A loaded identity
    /// stays untouched unless `restart` explicitly requests a fresh session.
    @discardableResult
    func load(_ url: URL, index: Int, restart: Bool, preservePosition: Bool = false) -> Bool {
        guard restart || self.index != index || self.url != url else { return false }
        unload()
        if restart || !preservePosition || urls[index] != url { positions[index] = nil }
        self.index = index
        self.url = url
        preservesPosition = preservePosition
        urls[index] = url
        resumeTime = preservePosition && !restart && positions[index]?.url == url ? positions[index]?.time : nil
        pendingStillFrame = resumeTime == nil ? nil : lastFrames[index]
        if resumeTime == nil { lastFrames[index] = nil }
        let asset = asset(for: url)
        looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(asset: asset))
        playbackSession &+= 1
        let generation = loadGeneration
        let metadata = assetStore.metadata[url]
        frameRate = metadata?.frameRate ?? 30
        hasVideoTrack = metadata?.hasVideoTrack ?? true
        if resumeTime != nil {
            // The looper can populate its queue asynchronously. Wait for that
            // actual item to be ready before issuing its one restoration seek.
            resumeQueueObservation = player.observe(\.currentItem, options: [.initial, .new]) { [weak self] _, _ in
                DispatchQueue.main.async { self?.restorePositionIfReady(generation: generation) }
            }
        }
        if metadata == nil {
            Task { [weak self] in
                let track = try? await asset.loadTracks(withMediaType: .video).first
                guard let self, self.loadGeneration == generation else { return }
                guard let track else {
                    self.hasVideoTrack = false
                    self.pause()
                    self.onPoster?()
                    return
                }
                if let rate = try? await track.load(.nominalFrameRate), rate > 0, self.loadGeneration == generation {
                    self.frameRate = rate
                    self.assetStore.metadata[url] = .init(frameRate: rate, hasVideoTrack: true)
                }
            }
        }
        refreshViews()
        return true
    }

    func play() {
        guard !isPlaying, looper != nil, !playbackFailed else { return }
        // isPlaying records playback intent while restoring; a background pause
        // can revoke it before the seek callback arrives.
        isPlaying = true
        if resumeTime == nil { player.play() }
    }

    /// Pauses on the current frame.
    func pause() {
        guard isPlaying else { return }
        isPlaying = false
        player.pause()
    }

    /// Forgets the loaded video and every card's frames; posters stay.
    func stop() {
        pause()
        unload()
        urls.removeAll()
        lastFrames.removeAll()
        positions.removeAll()
        refreshViews()
    }

    /// Preserve just the current feature's position and decoded still when its
    /// offscreen player is evicted. A pending seek owns the saved position until
    /// it succeeds; its transient queue time is never exported as a new playhead.
    func retainedPosition() -> RetainedPosition? {
        guard preservesPosition, let index, let url, urls[index] == url else { return nil }
        let time = resumeTime ?? player.currentTime()
        guard time.isNumeric, time.seconds.isFinite, time.seconds >= 0 else { return nil }
        return RetainedPosition(url: url, time: time, frame: lastFrames[index])
    }

    func restore(_ position: RetainedPosition, for index: Int) {
        urls[index] = position.url
        positions[index] = (position.url, position.time)
        lastFrames[index] = position.frame
    }

    private func unload() {
        if preservesPosition, let index, let url, urls[index] == url, resumeTime == nil {
            let time = player.currentTime()
            if time.isNumeric, time.seconds.isFinite, time.seconds >= 0 {
                positions[index] = (url, time)
            }
        }
        // An interrupted restoration keeps its saved nonzero time; the new
        // queue item's transient zero must never overwrite that position.
        loadGeneration &+= 1
        pause()
        resumeQueueObservation = nil
        resumeItemObservation = nil
        resumeObservedItem = nil
        player.currentItem?.cancelPendingSeeks()
        resumeTime = nil
        resumeSeeking = false
        resumeFailed = false
        pendingStillFrame = nil
        looper?.disableLooping()
        looper = nil
        player.removeAllItems()
        outputs.removeAll()
        index = nil
        url = nil
        hasFrame = false
    }

    private func restorePositionIfReady(generation: UInt64) {
        guard generation == loadGeneration, let saved = resumeTime, !resumeSeeking,
              let item = player.currentItem else { return }
        guard item.status != .failed else { finishRestoringPosition(generation: generation, succeeded: false); return }
        guard item.status == .readyToPlay else {
            if resumeObservedItem !== item {
                resumeObservedItem = item
                resumeItemObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] _, _ in
                    DispatchQueue.main.async { self?.restorePositionIfReady(generation: generation) }
                }
            }
            return
        }
        resumeQueueObservation = nil
        resumeItemObservation = nil
        resumeObservedItem = nil
        resumeSeeking = true
        // A loop boundary may be reported exactly at the duration. Restore the
        // corresponding position in its next cycle, never seek beyond the item.
        let duration = item.duration.seconds
        let seconds = duration.isFinite && duration > 0 ? saved.seconds.truncatingRemainder(dividingBy: duration) : saved.seconds
        let target = CMTime(seconds: seconds, preferredTimescale: 60_000)
        player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
            DispatchQueue.main.async { self?.finishRestoringPosition(generation: generation, succeeded: finished) }
        }
    }

    private func finishRestoringPosition(generation: UInt64, succeeded: Bool) {
        guard generation == loadGeneration, resumeTime != nil else { return }
        resumeQueueObservation = nil
        resumeItemObservation = nil
        resumeObservedItem = nil
        resumeSeeking = false
        resumeFailed = !succeeded
        if succeeded { resumeTime = nil }
        if succeeded && isPlaying { player.play() }
        else if !succeeded { pause() }
        refreshViews()
        onPoster?()
    }

    private var playbackFailed: Bool {
        resumeFailed || !hasVideoTrack || player.status == .failed || looper?.status == .failed || player.currentItem?.status == .failed
    }

    private func asset(for url: URL) -> AVURLAsset {
        assetStore.asset(for: url)
    }

    /// The video's first frame, drawn once per file; nil until it is ready.
    func poster(for url: URL) -> CGImage? {
        if let image = posters[url] { return image }
        guard posterLoads.insert(url).inserted else { return nil }
        let generator = AVAssetImageGenerator(asset: asset(for: url))
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        Task { [weak self] in
            guard let image = try? await generator.image(at: .zero).image else { return }
            self?.posters[url] = image
            self?.refreshViews()
            self?.onPoster?()
        }
        return nil
    }

    /// Card `index`'s video as a still: the frame it stopped on, or its first frame.
    func still(for index: Int) -> CGImage? {
        if let frame = lastFrames[index] {
            let image = CIImage(cvPixelBuffer: frame)
            if let still = images.createCGImage(image, from: image.extent) { return still }
        }
        return urls[index].flatMap { posters[$0] }
    }

    /// Whether the current item has a frame newer than the last one read for `hostTime`.
    func hasNewFrame(forHostTime hostTime: CFTimeInterval) -> Bool {
        if pendingStillFrame != nil { return true }
        guard resumeTime == nil else {
            if playbackFailed { pause() }
            return false
        }
        guard let output = currentOutput() else { return false }
        return output.hasNewPixelBuffer(forItemTime: output.itemTime(forHostTime: hostTime))
    }

    /// The current item's frame for `hostTime`, if it is newer than the last one read.
    func newFrame(forHostTime hostTime: CFTimeInterval) -> CVPixelBuffer? {
        if let frame = pendingStillFrame {
            pendingStillFrame = nil
            return frame
        }
        guard resumeTime == nil else {
            if playbackFailed { pause() }
            return nil
        }
        guard let index, let output = currentOutput() else { return nil }
        let time = output.itemTime(forHostTime: hostTime)
        guard output.hasNewPixelBuffer(forItemTime: time),
              let frame = output.copyPixelBuffer(forItemTime: time, itemTimeForDisplay: nil) else { return nil }
        lastFrames[index] = frame
        if !hasFrame {
            hasFrame = true
            refreshViews()
        }
        return frame
    }

    /// What an off-main fetch reads: the current item's output, tagged with this load.
    struct FrameRequest {
        let index: Int
        let generation: UInt64
        let output: AVPlayerItemVideoOutput
    }

    /// The output a background fetch may read now. A pending restored still is served on
    /// the main thread first, and a restoration seek owns the playhead until it finishes.
    func frameRequest() -> FrameRequest? {
        guard pendingStillFrame == nil else { return nil }
        guard resumeTime == nil else {
            if playbackFailed { pause() }
            return nil
        }
        guard let index, let output = currentOutput() else { return nil }
        return FrameRequest(index: index, generation: loadGeneration, output: output)
    }

    var hasPendingStill: Bool { pendingStillFrame != nil }

    func takePendingStill() -> CVPixelBuffer? {
        defer { pendingStillFrame = nil }
        return pendingStillFrame
    }

    /// Records a frame fetched off the main thread, as `newFrame` would, if its load is current.
    func accept(_ frame: CVPixelBuffer, from request: FrameRequest) -> Bool {
        guard request.generation == loadGeneration, request.index == index, resumeTime == nil else { return false }
        lastFrames[request.index] = frame
        if !hasFrame {
            hasFrame = true
            refreshViews()
        }
        return true
    }

    /// Any thread: the output's frame for `hostTime`, if newer than the last one copied.
    /// These calls wait on the media server, which is why they can leave the main thread.
    nonisolated static func fetch(_ request: FrameRequest, hostTime: CFTimeInterval) -> CVPixelBuffer? {
        let time = request.output.itemTime(forHostTime: hostTime)
        guard request.output.hasNewPixelBuffer(forItemTime: time) else { return nil }
        return request.output.copyPixelBuffer(forItemTime: time, itemTimeForDisplay: nil)
    }

    /// Each looping item gets its own output once it plays.
    private func currentOutput() -> AVPlayerItemVideoOutput? {
        guard !playbackFailed else { pause(); return nil }
        guard looper != nil, let item = player.currentItem else { return nil }
        if let output = outputs[ObjectIdentifier(item)] { return output }
        // The looper replaces queue items over time. Retain outputs only while their
        // item is queued so a long-lived feature hold cannot accumulate old decoders.
        let queued = Set(player.items().map(ObjectIdentifier.init))
        outputs = outputs.filter { queued.contains($0.key) }
        let output = AVPlayerItemVideoOutput(pixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferMetalCompatibilityKey as String: true
        ])
        item.add(output)
        outputs[ObjectIdentifier(item)] = output
        return output
    }

    /// A flat card's panel shows the player only once it shows that card's frames.
    func attach(_ view: CarouselPlayerView, index: Int) {
        views.removeAll { $0.view.view == nil || $0.view.view === view }
        views.append((index, WeakPlayerView(view: view)))
        show(view, index: index)
    }

    private func refreshViews() {
        views.removeAll { $0.view.view == nil }
        for entry in views { if let view = entry.view.view { show(view, index: entry.index) } }
    }

    private func show(_ view: CarouselPlayerView, index: Int) {
        let live = self.index == index && hasFrame
        view.show(player: live ? player : nil, still: still(for: index))
    }

    private struct WeakPlayerView {
        weak var view: CarouselPlayerView?
    }
}

/// Shared immutable asset metadata survives a feature player's eviction. Decoder
/// queues and output buffers still belong to the individual visible player.
@MainActor
final class CarouselVideoAssetStore {
    struct Metadata {
        let frameRate: Float
        let hasVideoTrack: Bool
    }

    private var assets: [URL: AVURLAsset] = [:]
    var metadata: [URL: Metadata] = [:]

    func asset(for url: URL) -> AVURLAsset {
        if let asset = assets[url] { return asset }
        let asset = AVURLAsset(url: url)
        assets[url] = asset
        return asset
    }
}

/// Feature movies remain live everywhere the Metal scene can sample them. A
/// covered card still contributes to refraction, so visibility comes from the
/// scene's source list, never nearest-index, screen bounds or occlusion tests.
@MainActor
final class CarouselFeatureVideoPlayback {
    private struct Entry {
        let playback: CarouselBackVideoPlayback
        /// Unique per player, so a fetch for an evicted one never reaches its replacement.
        let epoch: UInt64
        var offscreenTime: Double = 0
        var lastVisibleRevision: UInt64 = 0
    }

    /// Frames fetched off the main thread, newest per card, until the display clock takes them.
    nonisolated private final class FetchedFrames: @unchecked Sendable {
        struct Frame {
            let epoch: UInt64
            let request: CarouselBackVideoPlayback.FrameRequest
            let buffer: CVPixelBuffer
        }

        private let lock = NSLock()
        private var frames: [Int: Frame] = [:]
        private var busy = false
        private var generation: UInt64 = 0

        var isEmpty: Bool { lock.withLock { frames.isEmpty } }

        /// One fetch at a time: a slow media server never queues a backlog.
        func begin() -> UInt64? {
            lock.withLock {
                guard !busy else { return nil }
                busy = true
                return generation
            }
        }

        func finish(_ delivered: [Frame], generation started: UInt64) {
            lock.withLock {
                busy = false
                guard started == generation else { return }
                for frame in delivered { frames[frame.request.index] = frame }
            }
        }

        func take() -> [Int: Frame] {
            lock.withLock {
                defer { frames.removeAll() }
                return frames
            }
        }

        /// Drops delivered frames and any still in flight.
        func discard() {
            lock.withLock {
                generation &+= 1
                frames.removeAll()
            }
        }
    }

    static let offscreenGrace: Double = 0.5
    static let maximumParkedPlayers = 2
    private let assetStore = CarouselVideoAssetStore()
    private var entries: [Int: Entry] = [:]
    private var retained: [Int: CarouselBackVideoPlayback.RetainedPosition] = [:]
    private var revision: UInt64 = 0
    private var nextEpoch: UInt64 = 0
    private let fetchQueue = DispatchQueue(label: "com.metalforge.carousel.feature-video-frames",
                                           qos: .userInteractive)
    private let fetched = FetchedFrames()
    private(set) var activeIndices: Set<Int> = []
    var onFrameNeeded: (() -> Void)?

    var snapshots: [Int: CarouselBackVideoPlayback.Snapshot] {
        entries.mapValues { $0.playback.snapshot }
    }

    func snapshot(for index: Int) -> CarouselBackVideoPlayback.Snapshot? {
        entries[index]?.playback.snapshot
    }

    var isPlaying: Bool { entries.values.contains { $0.playback.isPlaying } }
    var frameRate: Float {
        entries.values.filter { $0.playback.isPlaying }.map { $0.playback.frameRate }.max() ?? 0
    }

    func update(frame: CarouselFrame, media: [Int: CarouselFeatureMedia]) {
        revision &+= 1
        let indices = Set((frame.wheel + frame.promoted).filter {
            $0.pose.opacity > 0.001 && $0.pose.height > 0 && media[$0.index] != nil
        }.map(\.index))
        activeIndices = indices
        for index in Array(entries.keys) where !indices.contains(index) {
            entries[index]?.playback.pause()
        }
        for index in indices.sorted() {
            guard let source = media[index] else { continue }
            if entries[index] == nil {
                let playback = CarouselBackVideoPlayback(assetStore: assetStore)
                playback.onPoster = { [weak self] in self?.onFrameNeeded?() }
                if let position = retained.removeValue(forKey: index), position.url == source.url {
                    playback.restore(position, for: index)
                }
                nextEpoch &+= 1
                entries[index] = Entry(playback: playback, epoch: nextEpoch)
            }
            guard var entry = entries[index] else { continue }
            entry.offscreenTime = 0
            entry.lastVisibleRevision = revision
            entry.playback.load(source.url, index: index, restart: false, preservePosition: true)
            entry.playback.play()
            entries[index] = entry
        }
        // Reversing across the fade boundary reuses a recent queue. A fast throw
        // cannot accumulate decoder queues for every feature it passed through.
        let parked = entries.keys.filter { !indices.contains($0) }.sorted {
            let first = entries[$0]!.lastVisibleRevision, second = entries[$1]!.lastVisibleRevision
            return first == second ? $0 < $1 : first > second
        }
        for index in parked.dropFirst(Self.maximumParkedPlayers) { evict(index) }
    }

    /// Called only by the carousel's existing display clock.
    func advance(by dt: Double) {
        guard dt.isFinite, dt > 0 else { return }
        for index in Array(entries.keys) where !activeIndices.contains(index) {
            entries[index]?.offscreenTime += dt
            if (entries[index]?.offscreenTime ?? 0) >= Self.offscreenGrace { evict(index) }
        }
    }

    func hasNewFrame(forHostTime time: CFTimeInterval) -> Bool {
        activeIndices.contains { entries[$0]?.playback.hasNewFrame(forHostTime: time) == true }
    }

    func newFrames(forHostTime time: CFTimeInterval, consume: (Int, CVPixelBuffer) -> Void) {
        for index in activeIndices.sorted() {
            if let frame = entries[index]?.playback.newFrame(forHostTime: time) { consume(index, frame) }
        }
    }

    /// Whether a background fetch delivered a frame, or a restored still is waiting.
    var hasFetchedFrames: Bool {
        !fetched.isEmpty || activeIndices.contains { entries[$0]?.playback.hasPendingStill == true }
    }

    /// Starts one off-main fetch of every active video's frame for `time`, unless the
    /// previous fetch is still running. The display clock collects the result later.
    func fetchFrames(forHostTime time: CFTimeInterval) {
        guard let generation = fetched.begin() else { return }
        let requests = activeIndices.sorted().compactMap { index -> (UInt64, CarouselBackVideoPlayback.FrameRequest)? in
            guard let entry = entries[index], let request = entry.playback.frameRequest() else { return nil }
            return (entry.epoch, request)
        }
        let fetched = fetched
        guard !requests.isEmpty else { fetched.finish([], generation: generation); return }
        fetchQueue.async {
            let delivered = requests.compactMap { epoch, request in
                CarouselBackVideoPlayback.fetch(request, hostTime: time).map {
                    FetchedFrames.Frame(epoch: epoch, request: request, buffer: $0)
                }
            }
            fetched.finish(delivered, generation: generation)
        }
    }

    /// Hands over restored stills and fetched frames whose player and load are still current.
    func fetchedFrames(consume: (Int, CVPixelBuffer) -> Void) {
        let delivered = fetched.take()
        for index in activeIndices.sorted() {
            guard let entry = entries[index] else { continue }
            if let still = entry.playback.takePendingStill() {
                consume(index, still)
                continue
            }
            guard let frame = delivered[index], frame.epoch == entry.epoch,
                  entry.playback.accept(frame.buffer, from: frame.request) else { continue }
            consume(index, frame.buffer)
        }
    }

    func discardFetchedFrames() { fetched.discard() }

    func pause() { entries.values.forEach { $0.playback.pause() } }

    func stop() {
        fetched.discard()
        entries.values.forEach { $0.playback.stop() }
        entries.removeAll()
        retained.removeAll()
        activeIndices.removeAll()
    }

    private func evict(_ index: Int) {
        guard let entry = entries.removeValue(forKey: index) else { return }
        if let position = entry.playback.retainedPosition() { retained[index] = position }
        entry.playback.onPoster = nil
        entry.playback.stop()
    }
}

/// What the selected card's back video does in a frame (`CarouselMetalView.updateBackVideo`).
enum CarouselBackVideoPlan: Equatable {
    /// Nothing shows a back: forget the loaded video.
    case none
    /// A back still shows, but not the selected card's video: hold its frame.
    case paused
    /// The selected card is turning and has a video: load it (from its first frame on a new
    /// selection) and play it while the card shows its back.
    case show(index: Int, restart: Bool, playing: Bool)

    static func make(focusedIndex: Int?, promoted: [CarouselRenderedCard], hasVideo: (Int) -> Bool,
                     lastSelection: Int?,
                     isBackFacing: ((CarouselRenderedCard) -> Bool)? = nil) -> CarouselBackVideoPlan {
        if let focusedIndex, hasVideo(focusedIndex),
           let card = promoted.first(where: { $0.index == focusedIndex && $0.pose.turn != 0 }) {
            let playing = isBackFacing?(card) ?? (cos(card.pose.turn) < 0)
            return .show(index: focusedIndex, restart: lastSelection != focusedIndex, playing: playing)
        }
        return promoted.contains { $0.pose.turn != 0 } ? .paused : .none
    }
}

enum CarouselBackVideoFit {
    /// The share of a video shown along each axis when it fills a panel of another shape:
    /// the longer side is cropped evenly, as images are.
    static func fill(panel: CGSize, video: CGSize) -> SIMD2<Double> {
        guard panel.width > 0, panel.height > 0, video.width > 0, video.height > 0 else { return SIMD2(1, 1) }
        let panelAspect = Double(panel.width / panel.height), videoAspect = Double(video.width / video.height)
        return videoAspect > panelAspect ? SIMD2(panelAspect / videoAspect, 1) : SIMD2(1, videoAspect / panelAspect)
    }
}
