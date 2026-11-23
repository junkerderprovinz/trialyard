/**
 * Generates the light and dark TrialYard banners, 1600x500, on the pattern of
 * glimstone's gen-banner.mjs: the mark on the left, the name in Bree Serif Light
 * and the claim in Bree Light. Text is turned into SVG paths with opentype.js so
 * the banner looks the same everywhere without a font.
 *
 * Deps (global): opentype.js, @resvg/resvg-js, and the house fonts as TTF in
 * HOUSE_FONTS (default %LOCALAPPDATA%\halleluja-fonts).
 *
 *   node .github/assets/gen-banner.mjs
 */
import { readFileSync, writeFileSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { tmpdir } from "node:os";
import { createRequire } from "node:module";
import { execSync } from "node:child_process";

const require = createRequire(import.meta.url);
const groot = execSync("npm root -g").toString().trim();
const opentype = require(`${groot}/opentype.js`);
const { Resvg } = require(`${groot}/@resvg/resvg-js`);

const __dir = dirname(fileURLToPath(import.meta.url));

const SLUG = "trialyard";
const NAME = "TrialYard";
const CLAIM = "Swing at it here.";
const MARK = join(__dir, "..", "..", "assets", "trialyard.svg");

const W = 1600, H = 500;
const LH = 400, LW = 400;
const nameSize = 132, claimSize = 44, gap = 70, lineGap = 8;

const THEMES = [
  { suffix: "", bg: "#ffffff", name: "#1f2328", claim: "#5a5d5e" },
  { suffix: "-dark", bg: "#0d1117", name: "#e6edf3", claim: "#9aa4ad" },
];

// The house typeface is licensed, so it is read from a local folder and never committed.
const fonts = process.env.HOUSE_FONTS ?? join(process.env.LOCALAPPDATA ?? tmpdir(), "halleluja-fonts");
const font = opentype.parse(readFileSync(join(fonts, "bree-serif-light.ttf")).buffer);
const claimFont = opentype.parse(readFileSync(join(fonts, "bree-light.ttf")).buffer);

const startX = 165;
const LX = startX, LY = (H - LH) / 2;
const textX = startX + LW + gap;

const sc = (s) => s / font.unitsPerEm;
const nameAsc = font.ascender * sc(nameSize);
const nameDesc = -font.descender * sc(nameSize);
const claimAsc = claimFont.ascender * (claimSize / claimFont.unitsPerEm);
const claimDesc = -claimFont.descender * (claimSize / claimFont.unitsPerEm);
const blockH = nameAsc + nameDesc + lineGap + claimAsc + claimDesc;
const nameBaseline = H / 2 - blockH / 2 + nameAsc;
const claimBaseline = nameBaseline + nameDesc + lineGap + claimAsc;

function textGroups(fnt, text, fontSize, x0, y0) {
  const scale = fontSize / fnt.unitsPerEm;
  let cx = x0;
  const parts = [];
  for (let i = 0; i < text.length; i++) {
    const glyph = fnt.charToGlyph(text[i]);
    const d = glyph.getPath(0, 0, fontSize).toPathData(2);
    parts.push(`<g transform="translate(${cx.toFixed(2)},${y0.toFixed(2)})"><path d="${d}"/></g>`);
    cx += glyph.advanceWidth * scale;
    if (i < text.length - 1) {
      cx += fnt.getKerningValue(glyph, fnt.charToGlyph(text[i + 1])) * scale;
    }
  }
  return parts.join("");
}

function embedMark(x, y, w, h) {
  const raw = readFileSync(MARK, "utf8").replace(/<\?xml[^>]*\?>\s*/, "");
  const vb = (raw.match(/viewBox="([^"]+)"/) || [, "0 0 1000 1000"])[1];
  return raw.replace(
    /<svg\b[^>]*>/,
    `<svg x="${x.toFixed(1)}" y="${y.toFixed(1)}" width="${w}" height="${h}" viewBox="${vb}" xmlns="http://www.w3.org/2000/svg">`,
  );
}

for (const t of THEMES) {
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="${W}" height="${H}" viewBox="0 0 ${W} ${H}">
  <rect width="${W}" height="${H}" fill="${t.bg}"/>
  ${embedMark(LX, LY, LW, LH)}
  <g fill="${t.name}">${textGroups(font, NAME, nameSize, textX, nameBaseline)}</g>
  <g fill="${t.claim}">${textGroups(claimFont, CLAIM, claimSize, textX, claimBaseline)}</g>
</svg>
`;
  const base = `${SLUG}-banner${t.suffix}`;
  writeFileSync(join(__dir, `${base}.svg`), svg);
  writeFileSync(join(__dir, `${base}.png`),
    new Resvg(svg, { background: t.bg, fitTo: { mode: "width", value: W } }).render().asPng());
  console.log(`wrote ${base}.svg + .png`);
}
