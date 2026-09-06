import js from "@eslint/js";
import tseslint from "typescript-eslint";
import globals from "globals";
import reactHooks from "eslint-plugin-react-hooks";

const reactHooksFlat = reactHooks.configs["recommended-latest"];

export default tseslint.config(
  {
    ignores: [
      "**/node_modules/**",
      "**/dist/**",
      "**/target/**",
      "**/.cache/**",
      "**/*.d.ts",
      "apps/app/**",
    ],
  },
  {
    name: "mindtree/base",
    files: ["**/*.ts", "**/*.tsx"],
    extends: [js.configs.recommended, ...tseslint.configs.recommended],
  },
  {
    name: "mindtree/browser",
    files: ["apps/{web,desktop,studio}/**/*.{ts,tsx}", "packages/ui/**/*.{ts,tsx}"],
    languageOptions: {
      globals: { ...globals.browser },
    },
  },
  {
    name: "mindtree/node",
    files: ["server/**/*.ts", "packages/{types,graph,tauri-common}/**/*.ts"],
    languageOptions: {
      globals: { ...globals.node },
    },
  },
  {
    name: "mindtree/react-hooks",
    files: ["apps/{web,desktop,studio}/**/*.{ts,tsx}", "packages/ui/**/*.{ts,tsx}"],
    plugins: reactHooksFlat.plugins,
    rules: reactHooksFlat.rules,
  },
);