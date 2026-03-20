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

test("deleteSheetAt remove chapa e ajusta indices apenas das chapas posteriores", () => {
  const appJs = readAppJs();
  assert.match(appJs, /function deleteSheetAt\(index\) \{/);
  assert.match(appJs, /sheetState\.splice\(idx, 1\);/);
  assert.match(appJs, /if \(normalized > idx\) \{\s*part\.userData\.sheetIndex = normalized - 1;/);
});

test("atalho Delete remove chapa ativa quando foco esta no painel de chapas ou sem peca selecionada", () => {
  const appJs = readAppJs();
  assert.match(appJs, /const sheetFocused = !!sheetListEl && sheetListEl\.contains\(document\.activeElement\);/);
  assert.match(appJs, /if \(sheetFocused \|\| !selectedPart\) \{\s*deleteSheetAt\(activeSheetIndex\);/);
});
