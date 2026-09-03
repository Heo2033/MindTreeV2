import type { FastifyInstance } from "fastify";
import { AITutorService } from "../domain/AITutorService.js";

export async function tutorRoutes(app: FastifyInstance) {
  // Потоковый чат (SSE): токены приходят по мере генерации, как в ChatGPT.
  app.post("/stream", async (request, reply) => {
    const { topic_id, session_id, message, node_id } = request.body as any;

    if (!topic_id || !message) {
      return reply.status(400).send({ error: "topic_id and message are required" });
    }

    reply.raw.writeHead(200, {
      "Content-Type": "text/event-stream",
      "Cache-Control": "no-cache",
      Connection: "keep-alive",
      "X-Accel-Buffering": "no",
    });

    const sendEvent = (event: string, data: any) => {
      reply.raw.write(`event: ${event}\ndata: ${JSON.stringify(data)}\n\n`);
    };

    // Сразу флашим заголовки + стартовый фрейм, чтобы клиент мгновенно увидел
    // живое соединение (fetch в postSSE резолвится по заголовкам) и показал
    // состояние «генерация», а не мёртвый спиннер при долгом ожидании слота.
    sendEvent("start", { at: Date.now() });

    const tutor = new AITutorService();
    const abortController = new AbortController();
    request.raw.on("close", () => {
      if (request.raw.destroyed || reply.raw.destroyed) {
        abortController.abort();
      }
    });

    try {
      const stream = tutor.streamReply(topic_id, message, {
        sessionId: session_id,
        nodeId: node_id,
        signal: abortController.signal,
      });

      for await (const event of stream) {
        if (abortController.signal.aborted) break;
        if (event.kind === "token") {
          sendEvent("token", { text: event.text });
        } else {
          sendEvent("done", {
            usedFallback: event.usedFallback,
            timeRemainingMinutes: event.timeRemainingMinutes,
            context: { topic_id, session_id, node_id },
          });
        }
      }
    } catch (err) {
      if (!abortController.signal.aborted) {
        sendEvent("error", {
          message: `Не удалось получить ответ: ${err instanceof Error ? err.message : String(err)}`,
        });
      }
    }

    reply.raw.end();
  });

  // Обратная совместимость: не-стриминговый вариант (весь текст в конце).
  app.post("/", async (request, reply) => {
    const { topic_id, session_id, message, node_id } = request.body as any;

    if (!topic_id || !message) {
      return reply.status(400).send({ error: "topic_id and message are required" });
    }

    const tutor = new AITutorService();
    const result = await tutor.reply(topic_id, message, {
      sessionId: session_id,
      nodeId: node_id,
    });

    return reply.send({
      response: result.text,
      usedFallback: result.usedFallback,
      timeRemainingMinutes: result.timeRemainingMinutes,
      context: { topic_id, session_id, node_id },
    });
  });
}
