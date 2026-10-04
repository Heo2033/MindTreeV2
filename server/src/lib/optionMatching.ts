// Единый резолв correctAnswer с вариантами ответа.
function normalizeOptionText(input: string): string {
  const buffer: string[] = [];
  const s = input.trim().toLowerCase();
  let i = 0;
  let lastWasSpace = false;
  while (i < s.length) {
    const c = s.charCodeAt(i);
    if (c === 32 || c === 9 || c === 10 || c === 13 || c === 11 || c === 12) {
      if (!lastWasSpace && buffer.length > 0) {
        buffer.push(" ");
        lastWasSpace = true;
      }
      i++;
      continue;
    }
    if (c === 44 || c === 46 || c === 59 || c === 58 || c === 33 || c === 63 || c === 45 || c === 95 || c === 40 || c === 41 || c === 91 || c === 93 || c === 123 || c === 125 || c === 34 || c === 39 || c === 96) {
      if (!lastWasSpace && buffer.length > 0) {
        buffer.push(" ");
        lastWasSpace = true;
      }
      i++;
      continue;
    }
    buffer.push(s[i]);
    lastWasSpace = false;
    i++;
  }
  return buffer.join("").trim();
}

export function resolveCorrectOptionIndex(options: string[], correctAnswer?: string): number | null {
  if (options.length === 0) return null;
  const raw = (correctAnswer ?? "").trim();
  if (raw.length === 0) return null;
  const asIndex = parseInt(raw, 10);
  if (!isNaN(asIndex) && asIndex >= 0 && asIndex < options.length) {
    return asIndex;
  }
  const target = normalizeOptionText(raw);
  if (target.length === 0) return null;
  for (let i = 0; i < options.length; i++) {
    const opt = normalizeOptionText(options[i]);
    if (opt.length > 0 && opt === target) {
      return i;
    }
  }
  return null;
}

export function resolveCorrectAnswerIndex(options: string[], correctAnswer?: string): string {
  const idx = resolveCorrectOptionIndex(options, correctAnswer);
  return idx === null ? "" : idx.toString();
}