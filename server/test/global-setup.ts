import { initDatabase } from "../src/db/connection.js";

export default function globalSetup() {
  initDatabase();
  return () => {};
}
