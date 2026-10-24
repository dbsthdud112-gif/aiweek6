// 사용법: node page_replace.mjs 입력.md 쪽그림폴더 쪽범위 출력.md "이전=>새" ...
//   쪽그림폴더: `kordoc render 원본 -d 폴더`로 만든 page_001.svg … (원본 기준)
//   쪽범위: 1 / 2-4 / 1,3
// 각 줄이 몇 쪽에 있는지 쪽 그림의 글자와 순서대로 맞춰 보고, 정한 쪽에 있는 줄에서만 값을 바꾼다.
// 이전 값이 들어 있는데 쪽을 찾지 못한 줄(쪽 경계에 걸친 문단 등)이 있으면 바꾸지 않고 종료 코드 1.
import { readFileSync, writeFileSync, readdirSync } from "node:fs";

const [input, pagesDir, range, output, ...args] = process.argv.slice(2);
if (!input || !pagesDir || !range || !output || !args.length) {
  console.error('사용법: node page_replace.mjs 입력.md 쪽그림폴더 쪽범위 출력.md "이전=>새" ...');
  process.exit(2);
}

const want = new Set();
for (const part of range.split(",")) {
  const [a, b] = part.split("-").map(Number);
  if (!a || (b && b < a)) { console.error(`잘못된 쪽범위: ${range}`); process.exit(2); }
  for (let p = a; p <= (b || a); p++) want.add(p);
}

const pairs = [];
for (const a of args) {
  const i = a.indexOf("=>");
  if (i <= 0) { console.error(`잘못된 값: ${a}`); process.exit(2); }
  if (!pairs.some(p => p.old === a.slice(0, i))) pairs.push({ old: a.slice(0, i), new: a.slice(i + 2) });
}
const escapeRe = s => s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
const map = Object.fromEntries(pairs.map(p => [p.old, p.new]));
const re = new RegExp([...pairs].sort((a, b) => b.old.length - a.old.length).map(p => escapeRe(p.old)).join("|"), "g");

// 마크다운 줄과 쪽 그림 글자를 같은 모양으로 맞춘다 (표 칸 구분, 머리 기호, 공백 제거)
const norm = s => s
  .replace(/<[^>]+>/g, "")
  .replace(/\\([~*_|#\-.])/g, "$1")
  .replace(/^\s*(#+|[-*]|>)\s*/, "")
  .replace(/\|/g, "")
  .replace(/---/g, "")
  .replace(/\s+/g, "");
const unent = s => s.replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&quot;/g, '"').replace(/&amp;/g, "&");

const files = readdirSync(pagesDir).filter(f => /^page_\d+\.svg$/.test(f)).sort();
if (!files.length) { console.error(`쪽 그림이 없음: ${pagesDir}`); process.exit(2); }
for (const p of want) if (p > files.length) { console.error(`문서는 ${files.length}쪽인데 ${p}쪽을 정함`); process.exit(2); }

const pageText = files.map(f =>
  [...readFileSync(`${pagesDir}/${f}`, "utf8").matchAll(/<text[^>]*>([^<]*)<\/text>/g)]
    .map(m => unent(m[1])).join("").replace(/\s+/g, ""));
const used = pageText.map(() => []);

// 앞쪽부터 찾되, 이미 짝지은 자리는 건너뛴다 (여러 쪽에 같은 표 머리줄이 있어도 순서대로 짝지음)
function findPage(key, from) {
  for (let p = from; p < pageText.length; p++) {
    for (let i = pageText[p].indexOf(key); i !== -1; i = pageText[p].indexOf(key, i + 1)) {
      const end = i + key.length;
      if (!used[p].some(([s, e]) => i < e && end > s)) { used[p].push([i, end]); return p; }
    }
  }
  return -1;
}

const lines = readFileSync(input, "utf8").split("\n");
let cur = 0, unknown = 0;
const log = [];
const counts = Object.fromEntries(pairs.map(p => [p.old, 0]));
const out = lines.map((line, idx) => {
  const key = norm(line);
  if (!key) return line;
  const p = findPage(key, cur);
  const hasOld = re.test(line); re.lastIndex = 0;
  if (p === -1) {
    if (hasOld) { unknown++; log.push(`줄 ${idx + 1}: 쪽을 찾지 못함 → 바꾸지 않음`); }
    return line;
  }
  cur = p;
  if (!hasOld || !want.has(p + 1)) return line;
  log.push(`줄 ${idx + 1} (${p + 1}쪽): 바꿈`);
  return line.replace(re, m => { counts[m]++; return map[m]; });
});
writeFileSync(output, out.join("\n"));

console.log(`정한 쪽: ${[...want].join(", ")} / 문서 ${files.length}쪽`);
for (const p of pairs) console.log(`${p.old} → ${p.new}: ${counts[p.old]}곳`);
log.forEach(l => console.log(l));
if (unknown) { console.log(`쪽을 찾지 못한 줄(이전 값 포함): ${unknown}줄 — 사용자에게 알리고 멈춤`); process.exit(1); }
