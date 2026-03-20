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

test("visual da chapa possui helper para guias de vertice da espessura", () => {
  const appJs = readAppJs();
  assert.match(appJs, /function createSheetThicknessGuides\(minX, minY, maxX, maxY, topZ, bottomZ, colorHex\)/);
  assert.match(appJs, /const vertices = new Float32Array\(\[/);
  assert.match(appJs, /new THREE\.LineSegments\(geometry, material\)/);
});

test("rebuildSheetsVisuals adiciona so guias de vertice sem borda interna util", () => {
  const appJs = readAppJs();
  assert.match(appJs, /const thicknessGuides = createSheetThicknessGuides\(/);
  assert.match(appJs, /wrapper\.add\(thicknessGuides\);/);
  assert.doesNotMatch(appJs, /usableBorder/);
});
