import js from "@eslint/js";
import tseslint from "typescript-eslint";
import globals from "globals";

export default tseslint.config(
  {
    ignores: [
      "**/node_modules/**",
      "**/dist/**",
      "**/target/**",
      "**/.cache/**",
      "**/*.d.ts",
    ],
  },
  {
    name: "mindtree/base",
    files: ["**/*.ts", "**/*.tsx"],
    extends: [js.configs.recommended, ...tseslint.configs.recommended],
  },
  {
    name: "mindtree/node",
    files: ["server/**/*.ts", "packages/types/**/*.ts"],
    languageOptions: {
      globals: { ...globals.node },
    },
  },
);
