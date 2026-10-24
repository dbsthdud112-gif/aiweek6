// 사용법: node section_replace.mjs 입력.md 범위 출력.md "이전=>새" ...
//   범위: "2. 사업 개요" / "~2. 사업 개요" / "3. 추진 배경~5. 추진 일정" (range.mjs 참고)
// 제목으로 정한 범위 안의 줄에서만 값을 바꾼다. 제목을 못 찾거나 여러 곳에 맞으면 바꾸지 않고 종료 코드 1.
import { readFileSync, writeFileSync } from "node:fs";
import { findRange } from "./range.mjs";

const [input, spec, output, ...args] = process.argv.slice(2);
if (!input || !spec || !output || !args.length) {
  console.error('사용법: node section_replace.mjs 입력.md 범위 출력.md "이전=>새" ...');
  process.exit(2);
}

const pairs = [];
for (const a of args) {
  const i = a.indexOf("=>");
  if (i <= 0) { console.error(`잘못된 값: ${a}`); process.exit(2); }
  if (!pairs.some(p => p.old === a.slice(0, i))) pairs.push({ old: a.slice(0, i), new: a.slice(i + 2) });
}

const lines = readFileSync(input, "utf8").split("\n");
const r = findRange(lines, spec);
if (r.error) { console.error(r.error); process.exit(1); }

const esc = s => s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
const map = Object.fromEntries(pairs.map(p => [p.old, p.new]));
const re = new RegExp([...pairs].sort((a, b) => b.old.length - a.old.length).map(p => esc(p.old)).join("|"), "g");
const counts = Object.fromEntries(pairs.map(p => [p.old, 0]));
const out = lines.map((l, i) => (i >= r.start && i < r.end) ? l.replace(re, m => { counts[m]++; return map[m]; }) : l);
writeFileSync(output, out.join("\n"));

console.log(`범위: ${r.start + 1}~${r.end}줄 ("${lines[r.start].replace(/^#+\s*/, "")}"부터)`);
for (const p of pairs) console.log(`${p.old} → ${p.new}: ${counts[p.old]}곳`);
