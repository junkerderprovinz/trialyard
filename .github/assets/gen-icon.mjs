/**
 * Renders the icon from the mark in assets/: the bare mark on a transparent
 * square, with a margin so it does not touch the edge of the tile. Unraid takes
 * the copy next to this file, the image serves the one in assets/ as favicon
 * and PWA icon.
 *
 * Deps (global): @resvg/resvg-js.
 *
 *   node .github/assets/gen-icon.mjs
 */
import { readFileSync, writeFileSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { createRequire } from "node:module";
import { execSync } from "node:child_process";

const require = createRequire(import.meta.url);
const { Resvg } = require(`${execSync("npm root -g").toString().trim()}/@resvg/resvg-js`);

const __dir = dirname(fileURLToPath(import.meta.url));
const ASSETS = join(__dir, "..", "..", "assets");

const SIZE = 512;
const MARK = 440;

const mark = readFileSync(join(ASSETS, "trialyard.svg"), "utf8").replace(/<\?xml[^>]*\?>\s*/, "");
const viewBox = mark.match(/viewBox="([^"]+)"/)[1];
const inset = (SIZE - MARK) / 2;
const placed = mark.replace(
  /<svg\b[^>]*>/,
  `<svg x="${inset}" y="${inset}" width="${MARK}" height="${MARK}" viewBox="${viewBox}" xmlns="http://www.w3.org/2000/svg">`,
);
const png = new Resvg(
  `<svg xmlns="http://www.w3.org/2000/svg" width="${SIZE}" height="${SIZE}">${placed}</svg>`,
  { fitTo: { mode: "width", value: SIZE } },
).render().asPng();

for (const dir of [__dir, ASSETS]) writeFileSync(join(dir, "icon.png"), png);
console.log("wrote .github/assets/icon.png and assets/icon.png");
