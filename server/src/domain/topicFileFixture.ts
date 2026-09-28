// Разовая проверка паритета формата: печатает эталонный JSON файла темы.
// Запуск: npx tsx src/domain/topicFileFixture.ts
import type { KnowledgeNode, Relation, Sequence } from "@mindtree/types";
import { TopicFile, rescopeNodes, ONE_LINER_MAX_LENGTH } from "./TopicFile.js";
import { scopedSuffix } from "./scopedIds.js";

const SRC_TOPIC = "topic_src_aaaa";
const NEW_TOPIC = "topic_new_bbbb";
const EXPORTED_AT = "2026-01-01T00:00:00.000Z";

function tree(): KnowledgeNode[] {
  const s = scopedSuffix(SRC_TOPIC);
  return [
    {
      id: "n1_root" + s,
      topicId: "",
      parentId: null,
      level: 1,
      label: "Корень",
      oneLiner: "Обзор темы.",
      details: "Подробное описание Корня.",
      relations: [
        { from: "n1_root" + s, to: "n2_a" + s, type: "depends_on", label: "часть" },
      ] as Relation[],
      sequences: [
        {
          id: "seq1",
          label: "Путь",
          steps: [
            { conceptId: "n2_a" + s, order: 0, label: "первый" },
            { conceptId: "n4_b" + s, order: 1 },
          ],
        },
      ] as Sequence[],
      sources: [],
      importance: 0.5,
      difficulty: 0.5,
      estimatedTimeMinutes: 5,
      state: "new",
      contentLoaded: false,
      leaf: false,
    },
    {
      id: "n2_a" + s,
      topicId: "",
      parentId: "n1_root" + s,
      level: 2,
      label: "Ветка А",
      oneLiner: "Описание А.",
      details: "Подробное описание А.",
      conceptType: "mechanism",
      analogy: "Как шестерёнка.",
      relations: [],
      sequences: [],
      sources: [],
      importance: 0.5,
      difficulty: 0.5,
      estimatedTimeMinutes: 5,
      state: "new",
      contentLoaded: false,
      leaf: false,
    },
    {
      id: "n3_a1" + s,
      topicId: "",
      parentId: "n2_a" + s,
      level: 3,
      label: "Лист А1",
      oneLiner: "Описание А1.",
      details: "Подробное описание А1.",
      relations: [],
      sequences: [],
      sources: [],
      importance: 0.5,
      difficulty: 0.5,
      estimatedTimeMinutes: 5,
      state: "new",
      contentLoaded: false,
      leaf: true,
    },
    {
      id: "n4_b" + s,
      topicId: "",
      parentId: "n1_root" + s,
      level: 2,
      label: "Ветка Б",
      oneLiner: "Описание Б.",
      details: "Подробное описание Б.",
      relations: [],
      sequences: [],
      sources: ["src-1"],
      importance: 0.5,
      difficulty: 0.5,
      estimatedTimeMinutes: 5,
      state: "new",
      contentLoaded: false,
      leaf: true,
    },
  ];
}

function treeWithLongOneLiner(): KnowledgeNode[] {
  const s = scopedSuffix(SRC_TOPIC);
  return [
    {
      id: "n1_root" + s,
      topicId: "",
      parentId: null,
      level: 1,
      label: "Корень",
      oneLiner: "я".repeat(200),
      details: "Подробное описание Корня.",
      relations: [],
      sequences: [],
      sources: [],
      importance: 0.5,
      difficulty: 0.5,
      estimatedTimeMinutes: 5,
      state: "new",
      contentLoaded: false,
      leaf: true,
    },
  ];
}

const file = new TopicFile({
  sourceTopicId: SRC_TOPIC,
  exportedAt: EXPORTED_AT,
  topic: { name: "Математический анализ", goal: "overview", targetLevel: "basic_understanding", timeBudgetMinutes: 90 },
  nodes: tree(),
});
const text = file.toJsonString();

const again = TopicFile.fromJsonString(text).toJsonString();
if (again !== text) {
  console.error("TS: FAIL — второй проход валидного файла отличается");
  process.exit(1);
}
if (file.errors.length > 0) {
  console.error("TS: FAIL — эталонное дерево невалидно: " + file.errors.join("; "));
  process.exit(1);
}

const long = TopicFile.fromJsonString(
  new TopicFile({
    sourceTopicId: SRC_TOPIC,
    exportedAt: EXPORTED_AT,
    topic: { name: "Длинный one_liner", goal: "overview", targetLevel: "basic_understanding", timeBudgetMinutes: 60 },
    nodes: treeWithLongOneLiner(),
  }).toJsonString(),
);
if (long.errors.length > 0 || long.warnings.length === 0) {
  console.error("TS: FAIL — обрезка one_liner: errors=" + long.errors.join("; ") + " warnings=" + long.warnings.join("; "));
  process.exit(1);
}
if (long.nodes[0]!.oneLiner.length !== ONE_LINER_MAX_LENGTH) {
  console.error("TS: FAIL — one_liner не обрезан");
  process.exit(1);
}

const rescoped = rescopeNodes(TopicFile.fromJsonString(text).nodes, SRC_TOPIC, NEW_TOPIC);

process.stdout.write(text);
console.error(
  "TS OK: oneLiner=" + long.nodes[0]!.oneLiner.length +
  " warnings=[" + long.warnings.join("; ") + "]" +
  " rescopedIds=[" + rescoped.map((e) => e.id).join(", ") + "]",
);
