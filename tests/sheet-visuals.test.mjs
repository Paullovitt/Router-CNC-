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

test("visual da chapa possui helper para arestas 3D (espessura)", () => {
  const appJs = readAppJs();
  assert.match(appJs, /function createSheetVolumeEdges\(boxGeometry, colorHex\)/);
  assert.match(appJs, /new THREE\.EdgesGeometry\(boxGeometry\)/);
  assert.match(appJs, /new THREE\.LineSegments\(edgeGeometry, edgeMaterial\)/);
});

test("rebuildSheetsVisuals adiciona linhas de aresta na espessura da chapa", () => {
  const appJs = readAppJs();
  assert.match(appJs, /const thicknessEdges = createSheetVolumeEdges\(/);
  assert.match(appJs, /thicknessEdges\.position\.set\(centerX, centerY, plateZ\);/);
  assert.match(appJs, /wrapper\.add\(thicknessEdges\);/);
});
