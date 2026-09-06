import { build } from "esbuild";
import {
  cpSync,
  existsSync,
  mkdirSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { execPath } from "node:process";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const SIDECAR_DIR = path.join(__dirname, "sidecar");
const NODE_MODULES = path.join(SIDECAR_DIR, "node_modules");
const ROOT_NODE_MODULES = path.join(__dirname, "..", "node_modules");

// Копирует пакет из корневого node_modules (хоарено npm) в sidecar.
// require.resolve('pkg/package.json') падает для пакетов с exports-map,
// поэтому пакет ищем по реальному пути, а для вложенных (конфликт версий)
// — в node_modules уже скопированных родителей.
function copyPackage(name) {
  const subdir = name.startsWith("@") ? name.split("/").join("/") : name;
  const candidates = [];
  const direct = path.join(ROOT_NODE_MODULES, subdir);
  if (existsSync(direct)) candidates.push(direct);
  for (const parent of seen) {
    const parentSub = parent.startsWith("@")
      ? parent.split("/").join("/")
      : parent;
    const nested = path.join(
      NODE_MODULES,
      parentSub,
      "node_modules",
      subdir,
    );
    if (existsSync(path.join(nested, "package.json"))) candidates.push(nested);
  }
  const chosen = candidates.find((p) =>
    existsSync(path.join(p, "package.json")),
  );
  if (!chosen) return null;
  const dest = path.join(NODE_MODULES, subdir);
  cpSync(chosen, dest, { recursive: true });
  return path.join(dest, "package.json");
}

rmSync(SIDECAR_DIR, { recursive: true, force: true });
mkdirSync(path.join(SIDECAR_DIR, "dist"), { recursive: true });

// Сервер в проде зависит только от обычных (не workspace) пакетов:
// workspace @mindtree/types зашит в bundle, а все node_modules-зависимости
// остаются внешними и должны лежать в sidecar/node_modules физически.
const serverPkgPath = path.join(__dirname, "package.json");
const serverPkg = JSON.parse(readFileSync(serverPkgPath, "utf8"));

const bundledWorkspace = new Set(["@mindtree/types", "@mindtree/graph"]);

const queue = Object.entries(serverPkg.dependencies ?? {})
  .filter(([name]) => !bundledWorkspace.has(name))
  .map(([name]) => name);

const external = [];
const seen = new Set();
while (queue.length > 0) {
  const name = queue.shift();
  if (seen.has(name)) continue;
  seen.add(name);
  external.push(name);

  const pkgJsonPath = copyPackage(name);
  if (!pkgJsonPath) {
    console.warn(`[sidecar] skip unresolvable ${name}`);
    continue;
  }

  const pkg = JSON.parse(readFileSync(pkgJsonPath, "utf8"));
  const childDeps = Object.keys(pkg.dependencies ?? {}).filter(
    (n) => !bundledWorkspace.has(n),
  );
  for (const child of childDeps) {
    if (!seen.has(child)) queue.push(child);
  }
}

await build({
  entryPoints: [path.join(__dirname, "src/index.ts")],
  outfile: path.join(SIDECAR_DIR, "dist/index.js"),
  bundle: true,
  format: "esm",
  platform: "node",
  target: "node20",
  external,
  sourcemap: false,
  minify: false,
  legalComments: "none",
  logLevel: "info",
});

writeFileSync(
  path.join(SIDECAR_DIR, "package.json"),
  JSON.stringify(
    {
      name: "mindtree-server-sidecar",
      version: "0.1.0",
      private: true,
      type: "module",
      main: "dist/index.js",
    },
    null,
    2,
  ),
  "utf8",
);

// Запекаем исполняемый файл Node рядом с бандлом: один каталог sidecar
// полностью самодостаточен и в dev, и в релизе. Версия node.exe совпадает
// с runtime машины сборки (лучше всего собирать на целевой платформе).
const nodeBinDir = path.join(SIDECAR_DIR, "bin");
mkdirSync(nodeBinDir, { recursive: true });
const nodeBinName = process.platform === "win32" ? "node.exe" : "node";
const nodeDest = path.join(nodeBinDir, nodeBinName);
if (!existsSync(nodeDest)) {
  cpSync(execPath, nodeDest);
}

console.log(
  `[sidecar] assembled at ${SIDECAR_DIR} (${external.length} prod deps copied, node → ${nodeDest})`,
);