import Foundation
import CoreGraphics
import MixlingsArt

/// What the living world adds on top of a creature's normal look (§1, §13).
struct LivingLook: Equatable, Hashable, Sendable {
    var weather: WeatherKind = .none
    var item: CareItem? = nil
    var alive: AliveFrame = .none

    static let plain = LivingLook()

    var isPlain: Bool { weather == .none && item == nil && alive == .none }
}

/// THE ONLY file that touches MixlingsArt's living-world API (`Phenotype.weather/.item/.alive`,
/// `LivingWorld`, `MixlingsRenderer.renderRoom/renderJumpRope/renderGlyph`).
///
/// Everything is behind `MIXLINGS_ART_LIVING` (off by default; add it to
/// SWIFT_ACTIVE_COMPILATION_CONDITIONS in project.yml for app, widget and tests once the art
/// lands). With the flag off every function returns nil / the unchanged phenotype and the
/// callers draw simple SwiftUI fallbacks. If an art name or encoding changes, fix it HERE only.
enum ArtAdapter {
    /// True when MixlingsArt draws weather, items, alive frames, rooms, rope and glyphs.
    static var drawsLiving: Bool {
        #if MIXLINGS_ART_LIVING
        return true
        #else
        return false
        #endif
    }

    /// Room / yard canvas size (art: 64 x 48).
    static let sceneSize = CGSize(width: 64, height: 48)

    /// Jump-rope frames: 0...3 rope loop, 4 trip, 5 cheer.
    static let jumpRopeLoopFrames = 4
    static let jumpRopeTripFrame = 4
    static let jumpRopeCheerFrame = 5

    // MARK: Phenotype layers

    /// Adds weather / item / alive layers. Unchanged with the flag off.
    static func apply(_ look: LivingLook, to p: Phenotype) -> Phenotype {
        #if MIXLINGS_ART_LIVING
        var out = p
        out.weather = artWeather(look.weather)
        out.item = look.item.map(artItem) ?? 0
        out.alive = artAlive(look.alive)
        return out
        #else
        return p
        #endif
    }

    // MARK: Renderers

    /// 64x48 room with the pair living `scene` (§9). Nil with the flag off.
    static func roomImage(_ a: Phenotype, _ b: Phenotype, scene: LifeScene?, night: Bool,
                          weather: WeatherKind, decorations: Decorations) -> CGImage? {
        #if MIXLINGS_ART_LIVING
        let furniture = [1, 1, 1, 1, 1, decorations.contains(.garland) || decorations.contains(.lights) ? 1 : 0]
        let buf = MixlingsRenderer.renderRoom((a, b), scene: artScene(scene ?? .chatting),
                                              timeOfDay: night ? LivingWorld.nightTime : LivingWorld.day,
                                              weather: artWeather(weather), furniture: furniture)
        return buf.cgImage(scale: 1)
        #else
        return nil
        #endif
    }

    /// 64x48 jump-rope yard frame (§8). Nil with the flag off.
    static func jumpRopeImage(_ p: Phenotype, frame: Int) -> CGImage? {
        #if MIXLINGS_ART_LIVING
        let f = min(max(0, frame), LivingWorld.jumpRopeFrames - 1)
        return MixlingsRenderer.renderJumpRope(p, frame: f).cgImage(scale: 1)
        #else
        return nil
        #endif
    }

    /// 16x16 one-colour Lock Screen glyph for a scene; `nil` scene = jump rope glyph.
    /// Nil with the flag off (callers use `LifeScene.systemImage`).
    static func glyphImage(scene: LifeScene?) -> CGImage? {
        #if MIXLINGS_ART_LIVING
        let index = scene.map(artScene) ?? LivingWorld.jumpRopeGlyph
        return MixlingsRenderer.renderGlyph(scene: index).cgImage(scale: 1)
        #else
        return nil
        #endif
    }

    // MARK: Wellbeing (hooks for the artist)

    /// "Breathe with me" frame for `phase` in 0...1 (0 = fully out, 1 = fully in).
    /// TODO(art): return MixlingsArt breathing frames when they land. Nil = callers use
    /// `scaleEffect` on the normal sprite.
    static func breathingFrame(phase: Double, phenotype: Phenotype) -> CGImage? {
        _ = min(max(phase, 0), 1)
        return nil
    }

    // MARK: Encodings (fix here if the art changes)

    #if MIXLINGS_ART_LIVING
    static func artWeather(_ w: WeatherKind) -> Int {
        switch w {
        case .none: return LivingWorld.none
        case .rain: return LivingWorld.rain
        case .heat: return LivingWorld.heat
        case .snow: return LivingWorld.snow
        case .wind: return LivingWorld.wind
        case .night: return LivingWorld.night
        }
    }

    static func artItem(_ i: CareItem) -> Int {
        switch i {
        case .umbrella: return LivingWorld.umbrella
        case .water: return LivingWorld.waterBottle
        case .fan: return LivingWorld.fan
        case .sunHat: return LivingWorld.sunHat
        case .scarf: return LivingWorld.scarf
        case .beanie: return LivingWorld.beanie
        case .blanket: return LivingWorld.blanket
        case .jumpRope: return LivingWorld.jumpRope
        }
    }

    static func artAlive(_ a: AliveFrame) -> Int {
        switch a {
        case .none: return 0
        case .charging: return LivingWorld.charging
        case .lowPower: return LivingWorld.lowPower
        case .morning: return LivingWorld.morning
        }
    }

    /// Art has 7 room scenes; the rest borrow the closest one.
    static func artScene(_ s: LifeScene) -> Int {
        switch s {
        case .chess: return LivingWorld.chess
        case .painting: return LivingWorld.painting
        case .chatting, .pillowFort: return LivingWorld.chatting
        case .napping: return LivingWorld.napping
        case .stargazing: return LivingWorld.stargazing
        case .breakfast, .cooking, .dinner: return LivingWorld.breakfast
        case .homework, .backpack: return LivingWorld.homework
        case .meditating, .windDown: return LivingWorld.napping
        }
    }
    #endif
}
