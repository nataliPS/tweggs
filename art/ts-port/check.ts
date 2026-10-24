// Compare the TS port against art/golden/renders.json. Usage: node check.ts
import { readFileSync } from "node:fs";
import { render } from "./render.ts";

const golden = JSON.parse(readFileSync(new URL("../golden/renders.json", import.meta.url), "utf8"));
let ok = 0;
for (const [i, cs] of golden.cases.entries()) {
  const want = Buffer.from(cs.rgba_hex, "hex");
  const got = render(cs.pheno, cs.silhouette === true);
  let bad = -1;
  for (let k = 0; k < want.length; k++) if (want[k] !== got[k]) { bad = k; break; }
  if (bad < 0 && want.length === got.length) { ok++; continue; }
  const px = bad >> 2;
  console.log(`case ${i} ${JSON.stringify(cs.pheno)} sil=${cs.silhouette}: first diff pixel ${px} (x=${px % 32},y=${px >> 5}) ` +
    `want ${want.subarray(px * 4, px * 4 + 4).toString("hex")} got ${Buffer.from(got.subarray(px * 4, px * 4 + 4)).toString("hex")}`);
}
console.log(`${ok}/${golden.cases.length} match`);
process.exit(ok === golden.cases.length ? 0 : 1);
