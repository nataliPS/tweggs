# engine-ts

Reference implementation of [`docs/genome-spec.md`](../docs/genome-spec.md), also used for server-side validation. It has no runtime dependencies. Node ≥ 22.18 runs the `.ts` files directly through built-in type stripping, so there is no build step.

```sh
npm test          # node --test test/*.test.ts
npm run golden    # regenerate golden/vectors.json + Swift catalog
npm run gen:swift # regenerate only MixlingsKit/Sources/MixlingsGenome/Catalog.swift
npm run typecheck # optional, needs a global `tsc`
```

## Layout

- `src/hash.ts`: FNV-1a 32 over UTF-8 bytes, plus `hex8`
- `src/rng.ts`: mulberry32 (`next`, `float`, `int`)
- `src/catalog.ts`: `CATALOG`, the single source of truth for gene and variant data
- `src/genome.ts`: `express`, `breed`, `rarity`, `starter`, `childId`

## Golden vectors

`scripts/make-golden.ts` writes `golden/vectors.json`. The file holds a catalog snapshot, hash cases, mulberry32 sequences for 3 seeds, 50 breeding cases and 20 starter cases. Each case records its full inputs and the expected outputs. The script also copies the file to `MixlingsKit/Tests/MixlingsGenomeTests/Resources/vectors.json`.

The TS tests (`test/golden.test.ts`) and the Swift tests (`GoldenVectorTests.swift`) both replay every case, so the two engines must agree bit-for-bit.

**Rules**
- Any change to `catalog.ts` or the genetics requires `npm run golden`. Commit the regenerated JSON and `Catalog.swift` in the same change.
- The case inputs come from a fixed-seed RNG, so regenerating without logic changes produces an identical file.
- If a golden test fails after you changed the logic, you changed the rules. Bump the spec version, because the server would reject children bred under the old rules.
