import Foundation
import MixlingsGenome
import MixlingsArt
#if MIXLINGS_ART_V2
import CoreGraphics
#endif

/// Art-independent view of what a genome expresses. Kept separate from `MixlingsArt.Phenotype`
/// so mapping logic is testable even if the renderer's API shifts.
struct ExpressedTraits: Equatable, Sendable {
    var body: Int
    var eyes: Int
    var head: Int
    var pattern: Int
    var tail: Int
    var palette: Int
    var aura: Int
    /// Personality, not drawn.
    var temper: Int
    var shift: Int
    var seed: Int
}

enum PhenotypeMapper {
    /// Gene order (genome-spec §1). Index constants so nothing depends on string keys.
    enum Gene {
        static let body = 0, eyes = 1, head = 2, pattern = 3, tail = 4, palette = 5, aura = 6, temper = 7
    }

    /// Stable per-creature art seed: FNV-1a 32 of the creature id (genome-spec §3).
    /// Int is 64-bit on every iOS device, so UInt32 always fits without sign issues.
    static func seed(forCreatureId id: String) -> Int {
        Int(Hash.fnv1a32(id))
    }

    /// Expresses the genome. Invalid genomes (corrupt save) fall back to all-zero variants
    /// instead of crashing a widget.
    static func traits(genome: Genome, creatureId: String, paletteShift: Int) -> ExpressedTraits {
        let e = (try? Genetics.express(genome)) ?? Array(repeating: 0, count: Catalog.geneCount)
        return ExpressedTraits(
            body: e[Gene.body],
            eyes: e[Gene.eyes],
            head: e[Gene.head],
            pattern: e[Gene.pattern],
            tail: e[Gene.tail],
            palette: e[Gene.palette],
            aura: e[Gene.aura],
            temper: e[Gene.temper],
            shift: paletteShift,
            seed: seed(forCreatureId: creatureId)
        )
    }

    static func traits(for c: Creature) -> ExpressedTraits {
        traits(genome: c.genome, creatureId: c.id, paletteShift: c.paletteShift)
    }

    /// The only place that constructs `MixlingsArt.Phenotype`.
    /// TODO(art): adjust the initializer labels here if MixlingsArt's Phenotype init differs.
    static func phenotype(_ t: ExpressedTraits) -> Phenotype {
        Phenotype(
            body: t.body,
            eyes: t.eyes,
            head: t.head,
            pattern: t.pattern,
            tail: t.tail,
            palette: t.palette,
            aura: t.aura,
            shift: t.shift,
            seed: t.seed
        )
    }

    static func phenotype(for c: Creature) -> Phenotype {
        phenotype(traits(for: c))
    }

    // MARK: Art v2 adapter (retro A1 mood layer, A3 growth stages, A4 silhouettes)
    //
    // TODO(art): MixlingsArt is adding `Phenotype.mood`, `Phenotype.stage` (with defaults) and
    // `MixlingsRenderer.renderSilhouette`. Until that lands, these hooks compile to the old
    // behaviour. Enable by adding `MIXLINGS_ART_V2` to SWIFT_ACTIVE_COMPILATION_CONDITIONS in
    // project.yml. If the field types differ (e.g. enums instead of Int), fix ONLY `artStage`,
    // `artMood` and `silhouetteImage` below.

    /// Phenotype for drawing `c` at `stage` with an optional mood expression.
    /// `look` adds living-world layers through `ArtAdapter` (no-op unless `MIXLINGS_ART_LIVING`).
    static func phenotype(for c: Creature, stage: Stage, condition: Condition? = nil,
                          look: LivingLook = .plain) -> Phenotype {
        #if MIXLINGS_ART_V2
        var p = phenotype(for: c)
        p.stage = artStage(stage)
        p.mood = artMood(condition)
        return ArtAdapter.apply(look, to: p)
        #else
        return ArtAdapter.apply(look, to: phenotype(for: c))
        #endif
    }

    /// True once MixlingsArt draws per-stage proportions itself (no SwiftUI scaling needed).
    static var artDrawsStages: Bool {
        #if MIXLINGS_ART_V2
        return true
        #else
        return false
        #endif
    }

    #if MIXLINGS_ART_V2
    /// Assumed art encoding: 0 egg, 1 baby, 2 teen, 3 adult (same as `Stage.rawValue`).
    static func artStage(_ s: Stage) -> Int { s.rawValue }

    /// Assumed art encoding: 0 neutral/smile, 1 "o" (surprised/okay), 2 hungry wobble (sleepy).
    static func artMood(_ c: Condition?) -> Int {
        switch c {
        case .happy?, nil: return 0
        case .okay?: return 1
        case .sleepy?: return 2
        }
    }

    /// Lock Screen silhouette straight from the renderer (no aura, knocked-out eyes).
    static func silhouetteImage(_ p: Phenotype) -> CGImage? {
        MixlingsRenderer.renderSilhouette(p).cgImage(scale: 1)
    }
    #endif

    static func temperName(_ t: ExpressedTraits) -> String {
        let variants = Catalog.genes[Gene.temper].variants
        return variants.indices.contains(t.temper) ? variants[t.temper].name : "calm"
    }
}
