import AppKit
import Metal
import DopamineCore
import DopamineEffectConfetti
import DopamineEffectRipple
import DopamineEffectFail
import DopamineEffectSolarbloom

/// Builds an effect's host (from its own metallib bundle) + a `prepare` closure that
/// resolves a feeling and prepares the (concretely-typed) host, returning the params
/// it was prepared with. `prepare` is captured over the concrete `MetalOverlayHost`
/// because `prepare(params:)` lives there, not on the type-erased `DopamineEffectHost`.
private struct EffectFactory {
    let build: (MTLDevice) -> (host: any DopamineEffectHost,
                               prepare: (DopeResolveInput) -> [String: DopeValue])?
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

/// Resolve `fx` with the feeling, prepare the concretely-typed `host`, and return the
/// params it was prepared with (so the caller can read `durationMs`).
private func prepareClosure<C: PassConfig, E: DopamineCore.EffectFactory>(
    _ host: MetalOverlayHost<C>, _ fx: E
) -> (DopeResolveInput) -> [String: DopeValue] {
    { input in
        let params = (try? fx.resolve(input)) ?? [:]
        try? host.prepare(params: params)
        return params
    }
}

private let effectFactories: [String: EffectFactory] = [
    "confetti": EffectFactory { device in
        guard let lib = try? device.makeDefaultLibrary(bundle: ConfettiResources.bundle),
              let host = try? MetalOverlayHost(config: Confetti.passConfig(), device: device,
                                               library: lib, wantsShadow: false),
              let fx = try? Confetti() else { return nil }
        return (host, prepareClosure(host, fx))
    },
    "ripple": EffectFactory { device in
        guard let lib = try? device.makeDefaultLibrary(bundle: RippleResources.bundle),
              let host = try? MetalOverlayHost(config: Ripple.passConfig(), device: device,
                                               library: lib, wantsShadow: false),
              let fx = try? Ripple() else { return nil }
        return (host, prepareClosure(host, fx))
    },
    "solarbloom": EffectFactory { device in
        guard let lib = try? device.makeDefaultLibrary(bundle: SolarbloomResources.bundle),
              let host = try? MetalOverlayHost(config: Solarbloom.passConfig(), device: device,
                                               library: lib, wantsShadow: false),
              let fx = try? Solarbloom() else { return nil }
        return (host, prepareClosure(host, fx))
    },
    "fail": EffectFactory { device in
        guard let lib = try? device.makeDefaultLibrary(bundle: FailResources.bundle),
              let host = try? MetalOverlayHost(config: Fail.passConfig(), device: device,
                                               library: lib, wantsShadow: false),
              let fx = try? Fail() else { return nil }
        return (host, prepareClosure(host, fx))
    },
]

/// Owns Dopamine's `DesktopEffectOverlay` (the borderless, click-through, screen-saver-level
/// panel that bleeds effects past the app window with a radial fade and tracks it across
/// moves/displays) plus a per-effect host cache, and fires effects onto it.
@MainActor
final class EffectCoordinator {
    private struct Prepared {
        let host: any DopamineEffectHost
        let prepare: (DopeResolveInput) -> [String: DopeValue]
    }

    /// The desktop overlay. Exposed so the status menu can toggle whole-screen mode.
    let overlay: DesktopEffectOverlay
    private let device = MTLCreateSystemDefaultDevice()
    private var hosts: [String: Prepared] = [:]

    init(tracking window: NSWindow, margin: CGFloat = 200) {
        overlay = DesktopEffectOverlay(tracking: window, margin: margin)
    }

    private func prepared(_ name: String) -> Prepared? {
        if let existing = hosts[name] { return existing }
        guard let device, let built = effectFactories[name]?.build(device) else { return nil }
        let prepared = Prepared(host: built.host, prepare: built.prepare)
        hosts[name] = prepared
        return prepared
    }

    /// Re-resolve with a fresh seed, prepare, and present the named effect on the overlay.
    /// `anchorScreen` is a global screen point (AppKit bottom-left origin) the burst emanates
    /// from; nil centres it on the surface. The overlay maps it to surface-local itself.
    func fire(name: String, anchorScreen: CGPoint?) {
        guard let prepared = prepared(name) else { return }
        // Size the drawable to the overlay surface BEFORE prepare so hybrid panel textures
        // (confetti/solarbloom) build at the surface size, not the window's.
        prepared.host.lightLayer.drawableSize = overlay.surfaceSizePx
        let f = effectFeelings[name] ?? defaultFeeling
        let feeling = DopeResolveInput(mood: f.mood, intensity: f.intensity, whimsy: f.whimsy, seed: randomSeed())
        let params = prepared.prepare(feeling)

        var durationMs = 1800.0
        if case let .number(value)? = params["durationMs"] { durationMs = value }
        overlay.present(prepared.host, durationMs: durationMs,
                        anchorScreen: anchorScreen,
                        targetSizePt: effectTargetSizes[name] ?? defaultTargetSize)
    }
}
