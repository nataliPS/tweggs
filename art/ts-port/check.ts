// Compare the TS port against art/golden/renders.json. Usage: node check.ts
import { readFileSync } from "node:fs";
import { render, renderRoom, renderJumpRope, renderGlyph, renderCalm, renderWindDown } from "./render.ts";

const golden = JSON.parse(readFileSync(new URL("../golden/renders.json", import.meta.url), "utf8"));
let ok = 0, total = 0;
function cmp(label: string, want: Buffer, got: Uint8Array, w: number) {
  total++;
  let bad = -1;
  for (let k = 0; k < want.length; k++) if (want[k] !== got[k]) { bad = k; break; }
  if (bad < 0 && want.length === got.length) { ok++; return; }
  const px = bad >> 2;
  console.log(`${label}: first diff pixel ${px} (x=${px % w},y=${Math.floor(px / w)}) ` +
    `want ${want.subarray(px * 4, px * 4 + 4).toString("hex")} got ${Buffer.from(got.subarray(px * 4, px * 4 + 4)).toString("hex")}` +
    (want.length !== got.length ? ` len ${want.length} vs ${got.length}` : ""));
}
for (const [i, cs] of golden.cases.entries())
  cmp(`case ${i} ${JSON.stringify(cs.pheno)} sil=${cs.silhouette}`, Buffer.from(cs.rgba_hex, "hex"),
    render(cs.pheno, cs.silhouette === true), 32);
for (const [i, sc] of (golden.scenes ?? []).entries()) {
  const want = Buffer.from(sc.rgba_hex, "hex");
  const got = sc.kind === "room" ? renderRoom(sc.pair, sc.scene, sc.time_of_day, sc.weather, sc.furniture)
    : sc.kind === "jumprope" ? renderJumpRope(sc.pheno, sc.frame)
    : sc.kind === "calm" ? renderCalm(sc.pheno, sc.frame)
    : sc.kind === "winddown" ? renderWindDown(sc.pheno, sc.frame) : renderGlyph(sc.scene);
  cmp(`scene ${i} ${sc.kind} ${sc.scene ?? sc.frame}`, want, got, sc.width);
}
console.log(`${ok}/${total} match (${golden.cases.length} creatures, ${(golden.scenes ?? []).length} scenes)`);
process.exit(ok === total ? 0 : 1);
