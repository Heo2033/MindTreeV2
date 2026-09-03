import { initDatabase } from "./connection.js";

initDatabase();
console.log("Database schema is up to date.");
process.exit(0);