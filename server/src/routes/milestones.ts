import type { FastifyInstance } from "fastify";
import crypto from "crypto";
import { MASTERY_LEVELS } from "@mindtree/types";
import { MilestoneEngine, type Milestone } from "../domain/MilestoneEngine.js";
import { getDb } from "../db/connection.js";

function parseJsonArray<T>(raw: unknown, fallback: T[]): T[] {
  if (typeof raw !== "string" || raw.trim() === "") return fallback;
  try {
    const parsed = JSON.parse(raw);
    return Array.isArray(parsed) ? (parsed as T[]) : fallback;
  } catch {
    return fallback;
  }
}

function rowToMilestone(row: Record<string, unknown>): Milestone {
  return {
    id: String(row.id),
    level: String(row.level) as Milestone["level"],
    title: String(row.title),
    description: String(row.description),
    capabilities: parseJsonArray<string>(row.capabilities_json, []),
    estimatedHours: Number(row.estimated_hours),
    status: String(row.status) as Milestone["status"],
    alternativePaths: parseJsonArray<Milestone["alternativePaths"][number]>(
      row.alternative_paths_json,
      [],
    ),
  };
}

export async function milestoneRoutes(app: FastifyInstance) {
  const engine = new MilestoneEngine();

  app.post("/generate", async (request, reply) => {
    const { journey_id, topic_id } = request.body as any;
    if (!journey_id || !topic_id) {
      return reply.status(400).send({ error: "journey_id and topic_id are required" });
    }
    const milestones = await engine.generate(journey_id, topic_id);
    return reply.status(201).send({ milestones });
  });

  app.get("/journey/:journeyId", async (request, reply) => {
    const { journeyId } = request.params as { journeyId: string };
    const milestones = (getDb()
      .prepare(
        "SELECT * FROM learning_milestones WHERE journey_id = ? ORDER BY estimated_hours"
      )
      .all(journeyId) as Record<string, unknown>[]).map(rowToMilestone);
    return reply.send({ milestones });
  });

  app.patch("/:id", async (request, reply) => {
    const { id } = request.params as { id: string };
    const { status } = request.body as any;
    if (status) {
      getDb().prepare("UPDATE learning_milestones SET status = ? WHERE id = ?").run(status, id);
    }
    return reply.send({ ok: true });
  });

  app.post("/", async (request, reply) => {
    const body = (request.body ?? {}) as {
      journey_id?: string;
      level?: string;
      title?: string;
      description?: string;
      capabilities?: string[];
      estimatedHours?: number;
      status?: Milestone["status"];
    };
    if (!body.journey_id || !body.title || String(body.title).trim() === "") {
      return reply.status(400).send({ error: "journey_id and title are required" });
    }
    const id = `ms_${crypto.randomUUID().slice(0, 8)}`;
    const level = body.level && MASTERY_LEVELS.includes(body.level as any)
      ? (body.level as Milestone["level"])
      : "awareness";
    const capabilities = Array.isArray(body.capabilities)
      ? body.capabilities.filter((c) => typeof c === "string")
      : [];
    const status = body.status === "active" || body.status === "completed"
      ? body.status
      : "not_started";
    const estimatedHours =
      typeof body.estimatedHours === "number" && isFinite(body.estimatedHours)
        ? Math.max(0, body.estimatedHours)
        : 1;

    getDb()
      .prepare(
        `INSERT INTO learning_milestones
           (id, journey_id, level, title, description, capabilities_json, estimated_hours, status, alternative_paths_json)
         VALUES (?,?,?,?,?,?,?,?,?)`
      )
      .run(
        id,
        body.journey_id,
        level,
        String(body.title).trim(),
        String(body.description ?? ""),
        JSON.stringify(capabilities),
        estimatedHours,
        status,
        "[]",
      );

    return reply.status(201).send({
      milestone: rowToMilestone(
        getDb().prepare("SELECT * FROM learning_milestones WHERE id = ?").get(id) as Record<
          string,
          unknown
        >,
      ),
    });
  });

  app.delete("/:id", async (request, reply) => {
    const { id } = request.params as { id: string };
    const info = getDb().prepare("DELETE FROM learning_milestones WHERE id = ?").run(id);
    if (info.changes === 0) {
      return reply.status(404).send({ error: "milestone not found" });
    }
    return reply.send({ ok: true });
  });
}
