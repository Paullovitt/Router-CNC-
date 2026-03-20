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

test("visual da chapa possui helper para arestas 3D da espessura", () => {
  const appJs = readAppJs();
  assert.match(appJs, /function createSheetVolumeEdges\(boxGeometry, colorHex\)/);
  assert.match(appJs, /new THREE\.EdgesGeometry\(boxGeometry\)/);
  assert.match(appJs, /new THREE\.LineSegments\(edgeGeometry, edgeMaterial\)/);
});

test("rebuildSheetsVisuals adiciona arestas da espessura e borda interna util", () => {
  const appJs = readAppJs();
  assert.match(appJs, /const thicknessEdges = createSheetVolumeEdges\(/);
  assert.match(appJs, /isActive \? 0x38bdf8 : 0x475569/);
  assert.match(appJs, /thicknessEdges\.position\.set\(centerX, centerY, plateZ\);/);
  assert.match(appJs, /wrapper\.add\(thicknessEdges\);/);
  assert.match(appJs, /const usable = getSheetUsableBounds\(sheet, sheet\.originX, sheet\.originY\);/);
  assert.match(appJs, /const usableBorder = createSheetBorderLine\(/);
  assert.match(appJs, /wrapper\.add\(usableBorder\);/);
});

test("chapa ativa nao muda preenchimento; destaque fica so nas linhas de borda e margem", () => {
  const appJs = readAppJs();
  assert.match(appJs, /color: 0x19232f,/);
  assert.match(appJs, /emissive: 0x000000,/);
  assert.match(appJs, /emissiveIntensity: 0/);
  assert.match(appJs, /const border = createSheetBorderLine\([\s\S]*isActive \? 0x38bdf8 : 0x64748b/);
  assert.match(appJs, /const usableBorder = createSheetBorderLine\([\s\S]*isActive \? 0x22c55e : 0x4b5563/);
});
