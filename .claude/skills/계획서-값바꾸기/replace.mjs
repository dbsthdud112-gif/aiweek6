// 사용법: node replace.mjs 입력.md 출력.md "이전=>새" ...
// 이전 값들을 원문에서 한 번에 바꾼다. 긴 값을 먼저 맞추고, 바뀐 값은 다시 바꾸지 않는다.
import { readFileSync, writeFileSync } from "node:fs";

const [input, output, ...args] = process.argv.slice(2);
if (!input || !output || !args.length) {
  console.error('사용법: node replace.mjs 입력.md 출력.md "이전=>새" ...');
  process.exit(2);
}

const pairs = [];
for (const a of args) {
  const i = a.indexOf("=>");
  if (i <= 0) { console.error(`잘못된 값: ${a} ("이전=>새" 꼴이어야 함)`); process.exit(2); }
  const old = a.slice(0, i);
  if (!pairs.some(p => p.old === old)) pairs.push({ old, new: a.slice(i + 2) });
}

const escapeRe = s => s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
const map = Object.fromEntries(pairs.map(p => [p.old, p.new]));
const re = new RegExp(
  [...pairs].sort((a, b) => b.old.length - a.old.length).map(p => escapeRe(p.old)).join("|"),
  "g"
);

const text = readFileSync(input, "utf8");
const counts = Object.fromEntries(pairs.map(p => [p.old, 0]));
const out = text.replace(re, m => { counts[m]++; return map[m]; });
writeFileSync(output, out);

for (const p of pairs) console.log(`${p.old} → ${p.new}: ${counts[p.old]}곳`);
