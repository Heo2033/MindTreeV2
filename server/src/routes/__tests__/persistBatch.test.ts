import { describe, it, expect, beforeEach } from "vitest";
import { seedTopic } from "../../test/helpers.js";
import { getDb } from "../../db/connection.js";
import { persistBatch, reconcileTree } from "../pipeline.js";
import type { NodeDraft } from "../../domain/KnowledgeGraphEngine.js";

const topicId = "top_test_pb";

beforeEach(() => {
  const db = getDb();
  db.prepare("DELETE FROM knowledge_nodes").run();
  db.prepare("DELETE FROM topics").run();
  seedTopic(topicId, "Таро", { target_level: "solid_understanding" });
});

describe("persistBatch (инкрементальный персист уровней)", () => {
  it("сохраняет L1, затем L2, затем L3 отдельными партиями без сирот", async () => {
    const db = getDb();
    const root: NodeDraft[] = [{ id: "n1_root", title: "Таро", parentId: null, level: 1 }];
    await persistBatch(topicId, "Таро", root);
    let levels = (db.prepare("SELECT level FROM knowledge_nodes WHERE topic_id = ?").all(topicId) as { level: number }[]).map((r) => r.level);
    expect(levels).toEqual([1]);

    const l2: NodeDraft[] = [
      { id: "n2_a", title: "Старшие арканы", parentId: "n1_root", level: 2 },
      { id: "n2_b", title: "Младшие арканы", parentId: "n1_root", level: 2 },
    ];
    await persistBatch(topicId, "Таро", l2);
    levels = (db.prepare("SELECT level FROM knowledge_nodes WHERE topic_id = ?").all(topicId) as { level: number }[]).map((r) => r.level);
    expect(levels.sort()).toEqual([1, 2, 2]);

    // L3: родитель (n2_a) уже в БД из прошлой партии — не должен стать сиротой.
    const l3: NodeDraft[] = [
      { id: "n3_a1", title: "Шут", parentId: "n2_a", level: 3 },
      { id: "n3_a2", title: "Маг", parentId: "n2_a", level: 3 },
    ];
    await persistBatch(topicId, "Таро", l3);

    const orphanCount = (db.prepare(
      `SELECT COUNT(*) AS c FROM knowledge_nodes n
       WHERE n.topic_id = ? AND n.parent_id IS NOT NULL
         AND NOT EXISTS (SELECT 1 FROM knowledge_nodes p WHERE p.id = n.parent_id)`,
    ).get(topicId) as { c: number }).c;
    expect(orphanCount).toBe(0);
    const total = (db.prepare("SELECT COUNT(*) AS c FROM knowledge_nodes WHERE topic_id = ?").get(topicId) as { c: number }).c;
    expect(total).toBe(5);
  });

  it("пересчитывает leaf: родитель с детьми не остаётся листом", async () => {
    const db = getDb();
    await persistBatch(topicId, "Таро", [{ id: "n1_root", title: "Таро", parentId: null, level: 1 }]);
    await persistBatch(topicId, "Таро", [{ id: "n2_a", title: "Раздел", parentId: "n1_root", level: 2 }]);

    const rootLeaf = (db.prepare("SELECT leaf FROM knowledge_nodes WHERE label = 'Таро'").get() as { leaf: number }).leaf;
    expect(rootLeaf).toBe(0);

    // После добавления L3 родитель n2_a также уже не лист.
    await persistBatch(topicId, "Таро", [{ id: "n3_a1", title: "Дочь", parentId: "n2_a", level: 3 }]);
    const n2leaf = (db.prepare("SELECT leaf FROM knowledge_nodes WHERE label = 'Раздел'").get() as { leaf: number }).leaf;
    expect(n2leaf).toBe(0);
  });

  it("не сохраняет сирот (родитель отсутствует)", async () => {
    const db = getDb();
    await persistBatch(topicId, "Таро", [
      { id: "n3_orphan", title: "Без родителя", parentId: "nonexistent", level: 3 },
    ]);
    const count = (db.prepare("SELECT COUNT(*) AS c FROM knowledge_nodes WHERE topic_id = ?").get(topicId) as { c: number }).c;
    expect(count).toBe(0);
  });
});

describe("reconcileTree", () => {
  it("удаляет скелетные узлы, отсутствующие в финальном дереве", async () => {
    const db = getDb();
    await persistBatch(topicId, "Таро", [
      { id: "n1_root", title: "Таро", parentId: null, level: 1 },
      { id: "n2_dropped", title: "Отброшенный", parentId: "n1_root", level: 2 },
    ]);

    const finalTree: NodeDraft[] = [
      { id: "n1_root", title: "Таро", parentId: null, level: 1 },
      { id: "n2_kept", title: "Оставшийся", parentId: "n1_root", level: 2 },
    ];
    reconcileTree(topicId, finalTree);

    const remains = (db.prepare("SELECT label FROM knowledge_nodes WHERE topic_id = ?").all(topicId) as { label: string }[]).map((r) => r.label);
    expect(remains).not.toContain("Отброшенный");
    expect(remains).toContain("Таро");
  });

  it("не удаляет узлы с уже сгенерированным контентом", async () => {
    const db = getDb();
    await persistBatch(topicId, "Таро", [
      { id: "n1_root", title: "Таро", parentId: null, level: 1 },
      { id: "n2_content", title: "С контентом", parentId: "n1_root", level: 2 },
    ]);
    db.prepare("UPDATE knowledge_nodes SET content_loaded = 1 WHERE label = 'С контентом'").run();

    reconcileTree(topicId, [
      { id: "n1_root", title: "Таро", parentId: null, level: 1 },
    ]);

    const remains = (db.prepare("SELECT label FROM knowledge_nodes WHERE topic_id = ?").all(topicId) as { label: string }[]).map((r) => r.label);
    expect(remains).toContain("С контентом");
  });
});
