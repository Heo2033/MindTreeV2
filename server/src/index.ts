import { config } from "dotenv";
config();

import Fastify from "fastify";
import cors from "@fastify/cors";
import { initDatabase } from "./db/connection.js";
import { initRuntimeConfigFromFile } from "./config/runtimeConfig.js";
import { topicRoutes } from "./routes/topics.js";
import { sessionRoutes } from "./routes/sessions.js";
import { assessmentRoutes } from "./routes/assessments.js";
import { tutorRoutes } from "./routes/tutor.js";
import { pipelineRoutes } from "./routes/pipeline.js";
import { healthRoutes } from "./routes/health.js";
import { milestoneRoutes } from "./routes/milestones.js";
import { diagnosticRoutes } from "./routes/diagnostic.js";
import { treeRoutes } from "./routes/tree.js";
import { configRoutes } from "./routes/config.js";
import { quizRoutes } from "./routes/quiz.js";
import { learnerModelRoutes } from "./routes/learnerModel.js";
import { adminRoutes } from "./routes/admin.js";

const PORT = parseInt(process.env.PORT || "3000", 10);
const HOST = process.env.HOST || "0.0.0.0";

async function main() {
  const db = initDatabase();
  initRuntimeConfigFromFile();

  const app = Fastify({ logger: true });

  await app.register(cors, { origin: true });

  app.decorate("db", db);

  await app.register(healthRoutes);
  await app.register(topicRoutes, { prefix: "/api/topics" });
  await app.register(sessionRoutes, { prefix: "/api/sessions" });
  await app.register(assessmentRoutes, { prefix: "/api/assessments" });
  await app.register(tutorRoutes, { prefix: "/api/tutor" });
  await app.register(pipelineRoutes, { prefix: "/api/pipeline" });
  await app.register(milestoneRoutes, { prefix: "/api/milestones" });
  await app.register(diagnosticRoutes, { prefix: "/api/diagnostic" });
  await app.register(treeRoutes, { prefix: "/api/tree" });
  await app.register(configRoutes, { prefix: "/api/config" });
  await app.register(quizRoutes, { prefix: "/api/quiz" });
  await app.register(learnerModelRoutes, { prefix: "/api/learner-model" });
  await app.register(adminRoutes, { prefix: "/api/admin" });

  try {
    await app.listen({ port: PORT, host: HOST });
    console.log(`MindTree server running on http://${HOST}:${PORT}`);
  } catch (err) {
    app.log.error(err);
    process.exit(1);
  }
}

main();
