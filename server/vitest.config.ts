import { defineConfig } from "vitest/config";
import path from "path";
import { fileURLToPath } from "url";
import os from "os";

const __dirname = path.dirname(fileURLToPath(import.meta.url));

export default defineConfig({
  test: {
    root: __dirname,
    environment: "node",
    include: ["src/**/*.test.ts", "src/**/__tests__/**/*.test.ts"],
    globalSetup: ["./test/global-setup.ts"],
    setupFiles: ["./test/setup.ts"],
    // tests share one SQLite DB_PATH and the module-level `_db` singleton,
    // so files must not run in parallel.
    fileParallelism: false,
    env: {
      DB_PATH: path.join(os.tmpdir(), "mindtree-test-" + Date.now() + ".db"),
    },
  },
});
