import SwiftUI
import AppKit
import Metal
import QuartzCore
import simd
import DopamineCore
import DopamineEffectConfetti
import DopamineEffectRipple

/// Type-erases `MetalOverlayHost<Config>` (generic per effect) so hosts for
/// different effects can be held in one place. All members are already public.
protocol AnyEffectHost: AnyObject {
    var lightLayer: CAMetalLayer { get }
    var timeScale: Double { get set }
    func prepare(params: [String: DopeValue]) throws
    func play()
    func tick(now: CFTimeInterval, dpr: Float, anchorPx: SIMD2<Float>, targetPx: SIMD2<Float>)
}
extension MetalOverlayHost: AnyEffectHost {}

/// Builds an effect's host (from its own metallib bundle) + a feeling→params resolver.
private struct EffectFactory {
    let build: (MTLDevice) -> (host: any AnyEffectHost, resolve: (DopeResolveInput) -> [String: DopeValue])?
}

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
]

/// SwiftUI bridge: fires the named Dopamine effect (centered) whenever the event token changes.
struct EffectsOverlay: NSViewRepresentable {
    var event: Store.EffectEvent?

    func makeNSView(context: Context) -> EffectOverlayView { EffectOverlayView(frame: .zero) }

    func updateNSView(_ view: EffectOverlayView, context: Context) {
        guard let event, event.token != view.lastToken else { return }
        view.lastToken = event.token
        view.fire(name: event.name)
    }
}

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
    var lastToken = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
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

    // Soft glow effects don't need full 3× super-sampling; cap at 2×.
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

    /// Re-resolve with a fresh seed, prepare, and play the named effect (centered).
    func fire(name: String) {
        guard let prepared = prepared(name) else { return }
        if currentName != name {
            if let cur = currentName { hosts[cur]?.host.lightLayer.removeFromSuperlayer() }
            let layerToAttach = prepared.host.lightLayer
            layerToAttach.frame = bounds
            layerToAttach.contentsScale = renderScale
            layerToAttach.drawableSize = canvasPx()
            layer?.addSublayer(layerToAttach)
            currentName = name
        }
        let feeling = DopeResolveInput(mood: "celebratory", intensity: 0.85, whimsy: 0.5, seed: randomSeed())
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
        if let name = currentName, let prepared = hosts[name] {
            let l = prepared.host.lightLayer
            l.frame = bounds
            l.contentsScale = renderScale
            l.drawableSize = canvasPx()
        }
    }

    @objc private func tick() {
        let now = CACurrentMediaTime()
        if now > activeUntil {            // faded out → stop rendering entirely
            vsync?.isPaused = true
            return
        }
        guard let name = currentName, let prepared = hosts[name] else { return }
        let center = SIMD2<Float>(Float(bounds.midX), Float(bounds.midY))
        prepared.host.tick(now: now, dpr: Float(renderScale), anchorPx: center, targetPx: .zero)
    }
}
