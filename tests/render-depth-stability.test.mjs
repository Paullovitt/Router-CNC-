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

test("camera inicia com faixa de depth mais estável", () => {
  const appJs = readAppJs();
  assert.match(appJs, /new THREE\.PerspectiveCamera\(55, 1, 1, 120000\)/);
  assert.match(appJs, /const CAMERA_NEAR_MIN = 0\.8;/);
  assert.match(appJs, /const CAMERA_FAR_MARGIN = 3\.2;/);
});

test("ajuste dinâmico de near\/far é aplicado no fit e na animação", () => {
  const appJs = readAppJs();
  assert.match(appJs, /function updateCameraDepthRange\(/);
  assert.match(appJs, /updateCameraDepthRange\(\{\s*maxDimension: maxDim,/);
  assert.match(appJs, /cameraDistance: camera\.position\.distanceTo\(controls\.target\)/);
});

test("material transparente da chapa não escreve no depth buffer", () => {
  const appJs = readAppJs();
  assert.match(appJs, /depthWrite: false,/);
  assert.match(appJs, /polygonOffset: true,/);
  assert.match(appJs, /polygonOffsetUnits: 1,/);
});
