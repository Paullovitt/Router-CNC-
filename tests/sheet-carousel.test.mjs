import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const projectRoot = path.resolve(__dirname, "..");

function readAppJs() {
  return fs.readFileSync(path.join(projectRoot, "app.js"), "utf8");
}

test("carrossel de chapas usa origem 3D (originZ) e calcula layout circular", () => {
  const appJs = readAppJs();
  assert.match(appJs, /originZ: 0/);
  assert.match(appJs, /function computeSheetRingOrigins\(targetActiveIndex = activeSheetIndex\)/);
  assert.match(appJs, /const radius = Math\.max\(SHEET_RING_MIN_RADIUS, circumferenceTarget \/ \(Math\.PI \* 2\)\);/);
});

test("selecao de chapa dispara transicao animada sem rotacao continua", () => {
  const appJs = readAppJs();
  assert.match(appJs, /function startSheetRingTransition\(durationMs = SHEET_RING_TRANSITION_MS\)/);
  assert.match(appJs, /function updateSheetRingTransition\(nowMs = performance\.now\(\)\)/);
  assert.match(appJs, /setActiveSheet\(index, \{ animate = false \} = \{\}\)/);
  assert.match(appJs, /if \(animate\) \{\s*startSheetRingTransition\(\);/);
});

test("nova chapa entra no carrossel e vira ativa com animacao", () => {
  const appJs = readAppJs();
  assert.match(appJs, /newSheetBtn\.addEventListener\("click", \(\) => \{\s*sheetState\.push\(createSheetFrom\(\)\);/);
  assert.match(appJs, /setActiveSheet\(sheetState\.length - 1, \{ animate: true \}\);/);
});
