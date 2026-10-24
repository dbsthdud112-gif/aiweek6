// 제목 범위 해석 — section_replace.mjs와 check.sh가 같이 쓴다.
//   "제목"        → 그 제목부터 같은 단계 이상의 다음 제목 전까지
//   "~제목"       → 문서 처음부터 그 제목 전까지
//   "제목A~제목B" → 제목A부터 제목B 전까지
// 제목은 마크다운 제목(#) 줄에서 찾고, 정확히 하나만 맞아야 한다.
// 돌려주는 값: { start, end } (0부터 센 줄 번호, end는 포함 안 함) 또는 { error }

export function findRange(lines, spec) {
  const heads = lines
    .map((l, i) => { const m = l.match(/^(#+)\s+(.*)$/); return m ? { i, level: m[1].length, text: m[2] } : null; })
    .filter(Boolean);
  const all = heads.map(h => h.text).join(" / ");

  const find = q => {
    const hits = heads.filter(h => h.text.includes(q.trim()));
    if (hits.length === 1) return { head: hits[0] };
    if (!hits.length) return { error: `제목 "${q.trim()}"을(를) 찾지 못함. 문서의 제목: ${all || "(제목 없음)"}` };
    return { error: `제목 "${q.trim()}"이(가) ${hits.length}곳에 맞음: ${hits.map(h => h.text).join(" / ")}` };
  };

  let start, end;
  if (spec.includes("~")) {
    const [a, b] = spec.split("~");
    if (!a.trim() && !b.trim()) return { error: "범위가 비어 있음" };
    if (a.trim()) { const r = find(a); if (r.error) return r; start = r.head.i; } else start = 0;
    if (b.trim()) { const r = find(b); if (r.error) return r; end = r.head.i; } else end = lines.length;
  } else {
    const r = find(spec); if (r.error) return r;
    start = r.head.i;
    const next = heads.find(x => x.i > r.head.i && x.level <= r.head.level);
    end = next ? next.i : lines.length;
  }
  if (end <= start) return { error: "범위의 끝이 시작보다 앞에 있음" };
  return { start, end };
}
