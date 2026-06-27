import AppKit
import Metal
import QuartzCore
import simd
import DopamineCore
import DopamineEffectConfetti
import DopamineEffectRipple
import DopamineEffectFail
import DopamineEffectSolarbloom

/// Type-erases `MetalOverlayHost<Config>` (generic per effect) so hosts for
/// different effects can be held in one place. All members are already public.
protocol AnyEffectHost: AnyObject {
    var lightLayer: CAMetalLayer { get }
    var timeScale: Double { get set }
    func prepare(params: [String: DopeValue]) throws
    func play()
    func tick(now: CFTimeInterval, dpr: Float, anchorPx: SIMD2<Float>, targetPx: SIMD2<Float>)
    /// Hosts the overlay layer in `view` with orientation handled correctly
    /// (sets isGeometryFlipped per view.isFlipped). The single correct attach path.
    func attach(to view: NSView)
}
extension MetalOverlayHost: AnyEffectHost {}

/// Builds an effect's host (from its own metallib bundle) + a feeling→params resolver.
private struct EffectFactory {
    let build: (MTLDevice) -> (host: any AnyEffectHost, resolve: (DopeResolveInput) -> [String: DopeValue])?
}

/// Per-effect "feeling" (mood ∈ celebratory/electric/serene). Tweak intensity
/// (0…1) and whimsy (0…1) to scale each effect's energy.
private let effectFeelings: [String: (mood: String, intensity: Double, whimsy: Double)] = [
    "confetti":   ("electric", 0.25, 1.0),
    "fail":       ("serene", 0.01, 0.15),
    "solarbloom": ("electric", 0.05, 0.0),
]
private let defaultFeeling = (mood: "celebratory", intensity: 0.85, whimsy: 0.5)

/// Per-effect target box size (points). fail is half the size of the others.
private let effectTargetSizes: [String: CGSize] = [
    "confetti":   CGSize(width: 150, height: 150),
    "solarbloom": CGSize(width: 150, height: 150),
    "fail":       CGSize(width: 75, height: 75),
]
private let defaultTargetSize = CGSize(width: 150, height: 150)

private let effectFactories: [String: EffectFactory] = [
    "confetti": EffectFactory { device in
        guard let lib = try? device.makeDefaultLibrary(bundle: ConfettiResources.bundle),
              let host = try? MetalOverlayHost(config: Confetti.passConfig(), device: device,
                                               library: lib, wantsShadow: false),
              let fx = try? Confetti() else { return nil }
        return (host, { (try? fx.resolve($0)) ?? [:] })
    },
    "ripple": EffectFactory { device in
        guard let lib = try? device.makeDefaultLibrary(bundle: RippleResources.bundle),
              let host = try? MetalOverlayHost(config: Ripple.passConfig(), device: device,
                                               library: lib, wantsShadow: false),
              let fx = try? Ripple() else { return nil }
        return (host, { (try? fx.resolve($0)) ?? [:] })
    },
    "solarbloom": EffectFactory { device in
        guard let lib = try? device.makeDefaultLibrary(bundle: SolarbloomResources.bundle),
              let host = try? MetalOverlayHost(config: Solarbloom.passConfig(), device: device,
                                               library: lib, wantsShadow: false),
              let fx = try? Solarbloom() else { return nil }
        return (host, { (try? fx.resolve($0)) ?? [:] })
    },
    "fail": EffectFactory { device in
        guard let lib = try? device.makeDefaultLibrary(bundle: FailResources.bundle),
              let host = try? MetalOverlayHost(config: Fail.passConfig(), device: device,
                                               library: lib, wantsShadow: false),
              let fx = try? Fail() else { return nil }
        return (host, { (try? fx.resolve($0)) ?? [:] })
    },
]

/// Hosts the current effect's Metal layer and drives a display-link tick.
/// Pointer-transparent and idle (no GPU) until an effect is fired.
final class EffectOverlayView: NSView {
    private struct Prepared {
        let host: any AnyEffectHost
        let resolve: (DopeResolveInput) -> [String: DopeValue]
    }

    private let device = MTLCreateSystemDefaultDevice()
    private var hosts: [String: Prepared] = [:]
    private var currentName: String?
    private var vsync: CADisplayLink?
    private var activeUntil: CFTimeInterval = 0
    /// Radial alpha mask: effects fade out toward the overlay edges.
    private let fadeMask = CAGradientLayer()
    /// Where the effect emanates from, in this view's (flipped) local coords. nil = center.
    private var anchorPoint: CGPoint?
    /// Target box size (points) the effect concentrates within. .zero = effect default.
    private var targetSize: CGSize = .zero

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        fadeMask.type = .radial
        fadeMask.colors = [NSColor.white.cgColor, NSColor.white.cgColor, NSColor.clear.cgColor]
        fadeMask.locations = [0.0, 0.55, 1.0]
        fadeMask.startPoint = CGPoint(x: 0.5, y: 0.5)
        fadeMask.endPoint = CGPoint(x: 1.0, y: 1.0)
        layer?.mask = fadeMask
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) unused") }

    /// Top-left origin to match SwiftUI's coordinate space.
    override var isFlipped: Bool { true }
    /// Never intercept clicks — effects play over the live table.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil { startDisplayLink() }
    }

    private func startDisplayLink() {
        guard vsync == nil else { return }
        let link = displayLink(target: self, selector: #selector(tick))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
        link.add(to: .main, forMode: .common)
        link.isPaused = true   // idle until first fire
        vsync = link
    }

    // Cap at 2× (native Retina); enough for crisp effects without over-sampling.
    private var renderScale: CGFloat { min(window?.backingScaleFactor ?? 2, 2.0) }

    private func canvasPx() -> CGSize {
        let scale = renderScale
        return CGSize(width: max(bounds.width, 1) * scale, height: max(bounds.height, 1) * scale)
    }

    private func prepared(_ name: String) -> Prepared? {
        if let existing = hosts[name] { return existing }
        guard let device, let built = effectFactories[name]?.build(device) else { return nil }
        built.host.lightLayer.isOpaque = false
        built.host.lightLayer.contentsScale = renderScale
        built.host.lightLayer.drawableSize = canvasPx()
        let prepared = Prepared(host: built.host, resolve: built.resolve)
        hosts[name] = prepared
        return prepared
    }

    /// Re-resolve with a fresh seed, prepare, and play the named effect at `anchor`
    /// (this view's flipped local coords; nil = center). The target box size is
    /// looked up per effect.
    func fire(name: String, anchor: CGPoint? = nil) {
        anchorPoint = anchor
        self.targetSize = effectTargetSizes[name] ?? defaultTargetSize
        guard let prepared = prepared(name) else { return }
        if currentName != name {
            if let cur = currentName { hosts[cur]?.host.lightLayer.removeFromSuperlayer() }
            let l = prepared.host.lightLayer
            l.frame = bounds
            l.contentsScale = renderScale
            l.drawableSize = canvasPx()
            // attach(to:) hosts the layer with correct orientation (isGeometryFlipped
            // per self.isFlipped) — the single correct path; don't addSublayer manually.
            prepared.host.attach(to: self)
            currentName = name
        }
        let f = effectFeelings[name] ?? defaultFeeling
        let feeling = DopeResolveInput(mood: f.mood, intensity: f.intensity, whimsy: f.whimsy, seed: randomSeed())
        let params = prepared.resolve(feeling)
        try? prepared.host.prepare(params: params)
        prepared.host.play()

        var durationMs = 1800.0
        if case let .number(value)? = params["durationMs"] { durationMs = value }
        activeUntil = CACurrentMediaTime() + durationMs / 1000.0 + 0.5
        vsync?.isPaused = false
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)   // no implicit animation on resize/move
        fadeMask.frame = bounds
        if let name = currentName, let prepared = hosts[name] {
            let l = prepared.host.lightLayer
            l.frame = bounds
            l.contentsScale = renderScale
            l.drawableSize = canvasPx()
        }
        CATransaction.commit()
    }

    @objc private func tick() {
        let now = CACurrentMediaTime()
        if now > activeUntil {            // faded out → stop rendering entirely
            vsync?.isPaused = true
            return
        }
        guard let name = currentName, let prepared = hosts[name] else { return }
        let c = anchorPoint ?? CGPoint(x: bounds.midX, y: bounds.midY)
        let anchor = SIMD2<Float>(Float(c.x), Float(c.y))
        let target = SIMD2<Float>(Float(targetSize.width), Float(targetSize.height))
        prepared.host.tick(now: now, dpr: Float(renderScale), anchorPx: anchor, targetPx: target)
    }
}
