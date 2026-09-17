---
name: llm-pipeline
description: Используй когда нужно работать с LLM-инфраструктурой MindTree: TreeScheduler (RPM/RPD/retries/batch/cooldown), cache, telemetry, client (OpenAI/Ollama/auto, SSE, JSON repair), provider config, mock/офлайн-режим.
---

# LLM Pipeline — паттерны LLM-инфраструктуры

Используй при работе с LLM-слоем (`mindtree_flutter/lib/data/llm/*`, конфиг
`lib/config/*`; зеркала в `server/src/llm/*`).

## TreeScheduler

`lib/data/llm/scheduler.dart`: maxRPM=10, maxRPD=500, concurrency=2, retries=3, batchSize=3,
opDeadlineMs=120000. Возвращает `ExecuteResult` (текст/структура + `cached`).
Правила:
- Все LLM-вызовы движков — через `execute`/`executeStream`; прямое обращение к `client.dart`
  — только как низкоуровневый транспорт через scheduler.
- `configProvider` — читает актуальный `LLMConfig` (в т.ч. офлайн fallback до загрузки).

## Client и транспорт

- `callLLM`/`callLLMStream` (`client.dart`): OpenAI `/chat/completions`, Ollama `/api/chat`,
  provider `auto` → detection локального baseUrl (`localhost|127.0.0.1|0.0.0.0|[::1]`).
- Streaming: SSE-парсинг; `streamRejected` → fallback на non-stream.
- Rate-limit: `_rateLimitStatuses = {408, 429, 502, 503, 504}`; cooldown-карта с `retry-after`.
- Retry: `shouldRetry` — без retry для mock; `retryDelayMs` учитывает `retry-after`.

## Fallback и офлайн

- Каждый вызов движка имеет детерминированный fallback (fallback-текст, эвристика, mock).
- `LLM_MOCK`/`isMock` — заглушки без сетевых запросов (LLMMockException и т.д.) —
  пользовательский сценарий не падает.
- Invalid JSON: ограниченный retry → fallback/rejection; без бесконечных repair-loop.

## Cache / Telemetry

- `cache.dart`: fnv1a32-ключ по (операция+промпт+конфиг), TTL 24h, maxEntries 1000, диск.
- `telemetry.dart`: лог до 10000 записей, `aggregateStats`, `estimatedCost`,
  поля `op`, `model`, `latencyMs`, `cached`, `ok`.

## Тиры моделей

- strong: structure, structure-l2, structure-l3, validate, repair, quiz, curriculum,
  diagnostic, assessment, mastery, tutor, milestone.
- Маршрутизация: `tierForOperation(op)` → `modelForTier`/`modelsForTier`
  (strong fallback — `modelStrongFallback`).

## Конфиг провайдера

- `EffectiveConfig`: apiKey/baseUrl/model/modelStrong/modelStrongFallback/modelFast/
  temperature/numCtx/provider/isMock. Грузится через `ProviderConfigService`
  (secure storage) + dart-define `PROVIDER_MODE` (`hardcoded`|`configurable`).
- `tool/gen_config.ps1` генерирует `provider-config.json` из `server/.env`.
- Секреты не логировать и не коммитить.