#!/usr/bin/env bash
# 계획서 값 바꾸기 점검: 원본과 결과를 각각 마크다운으로 읽어 비교하고, 마크다운 보고서를 출력한다.
# 사용법: bash check.sh [-l patch.log] [-p 쪽범위 | -s 제목범위] 원본.hwp(x) 결과.hwp(x) "이전=>새" ...
#   -p 를 주면 원본·결과를 쪽 그림(render)으로도 그려, 정한 쪽만 바뀌고 다른 쪽은 그대로인지 쪽마다 센다.
#   -s 를 주면 제목 범위(range.mjs) 안만 바뀌고 범위 밖은 한 줄도 안 바뀌었는지 본다.
# 종료 코드: 0 모두 통과, 1 실패 있음, 2 사용법 오류

dir="$(cd "$(dirname "$0")" && pwd)"
log=""; pages=""; section=""
while [ $# -gt 0 ]; do
  case "$1" in
    -l) log="$2"; shift 2 ;;
    -p) pages="$2"; shift 2 ;;
    -s) section="$2"; shift 2 ;;
    *) break ;;
  esac
done
if [ $# -lt 3 ] || { [ -n "$pages" ] && [ -n "$section" ]; }; then
  echo '사용법: bash check.sh [-l patch.log] [-p 쪽범위 | -s 제목범위] 원본 결과 "이전=>새" ...' >&2
  exit 2
fi
orig="$1"; res="$2"; shift 2

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
mkdir "$tmp/a" "$tmp/b"
oext="${orig##*.}"; rext="${res##*.}"
cp "$orig" "$tmp/a/doc.$oext"; cp "$res" "$tmp/b/doc.$rext"
# 같은 이름(doc)으로 읽어야 이미지 경로가 같게 나온다
(cd "$tmp/a" && npx -y kordoc@^4 "doc.$oext" -o doc.md >/dev/null 2>&1) || { echo "원본을 읽지 못함: $orig" >&2; exit 1; }
(cd "$tmp/b" && npx -y kordoc@^4 "doc.$rext" -o doc.md >/dev/null 2>&1) || { echo "결과를 읽지 못함: $res" >&2; exit 1; }
if [ -n "$pages" ]; then
  (cd "$tmp/a" && npx -y kordoc@^4 render "doc.$oext" -d pages --silent >/dev/null 2>&1) || { echo "원본 쪽 그림 실패" >&2; exit 1; }
  (cd "$tmp/b" && npx -y kordoc@^4 render "doc.$rext" -d pages --silent >/dev/null 2>&1) || { echo "결과 쪽 그림 실패" >&2; exit 1; }
fi

srange=""
if [ -n "$section" ]; then
  srange="$(node -e '
const [lib, md, spec] = process.argv.slice(1);
import(require("url").pathToFileURL(lib).href).then(({ findRange }) => {
  const r = findRange(require("fs").readFileSync(md, "utf8").split("\n"), spec);
  if (r.error) { console.error(r.error); process.exit(1); }
  console.log(`${r.start} ${r.end}`);
});' "$dir/range.mjs" "$tmp/a/doc.md" "$section")" || { echo "제목 범위를 정하지 못함: $section" >&2; exit 1; }
fi

magic="$(head -c 2 "$res" | od -An -tx1 | tr -d ' \n')"
case "$magic" in 504b) real="hwpx" ;; d0cf) real="hwp" ;; *) real="알 수 없음" ;; esac

node - "$tmp" "$log" "$pages" "$srange" "$section" "$oext" "$rext" "$real" "$(basename "$orig")" "$(basename "$res")" "$@" <<'EOF'
const fs = require("fs");
const [tmp, log, pages, srange, section, oext, rext, real, oname, rname, ...args] = process.argv.slice(2);
const A = fs.readFileSync(`${tmp}/a/doc.md`, "utf8"), B = fs.readFileSync(`${tmp}/b/doc.md`, "utf8");

const pairs = [];
for (const a of args) {
  const i = a.indexOf("=>");
  if (i > 0 && !pairs.some(p => p.old === a.slice(0, i))) pairs.push({ old: a.slice(0, i), new: a.slice(i + 2) });
}
const count = (t, s) => { let n = 0, i = t.indexOf(s); while (s && i !== -1) { n++; i = t.indexOf(s, i + s.length); } return n; };
const esc = s => s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
const map = Object.fromEntries(pairs.map(p => [p.old, p.new]));
const re = new RegExp([...pairs].sort((x, y) => y.old.length - x.old.length).map(p => esc(p.old)).join("|"), "g");
const repl = s => s.replace(re, m => map[m]);

const out = [];
let fail = false;
const mark = ok => { if (!ok) fail = true; return ok ? "통과" : "**실패**"; };
const aL = A.split("\n"), bL = B.split("\n");

// 제목 범위: 범위 안만 센다
const [sS, sE] = srange ? srange.split(" ").map(Number) : [0, aL.length];
const inR = i => i >= sS && i < sE;

if (srange) {
  const Ain = aL.slice(sS, sE).join("\n"), Bin = bL.slice(sS, sE).join("\n");
  out.push(`## 제목 범위 점검 ("${section}" → ${sS + 1}~${sE}줄)`, "", "| 이전 값 | 새 값 | 범위 안 원본 건수 | 바뀐 횟수 | 범위 안 남은 이전 값 | 판정 |", "|---|---|---|---|---|---|");
  for (const p of pairs) {
    const o = count(Ain, p.old), rem = count(Bin, p.old), added = count(Bin, p.new) - count(Ain, p.new);
    const ok = (p.new.includes(p.old) || rem === 0) && added === o && o > 0;
    out.push(`| ${p.old} | ${p.new} | ${o} | ${added} | ${rem} | ${mark(ok)} |`);
  }
  let outside = 0;
  if (aL.length === bL.length) aL.forEach((l, i) => { if (!inR(i) && l !== bL[i]) outside++; });
  out.push("", `- 범위 밖에서 달라진 줄: ${outside} — ${mark(aL.length === bL.length && outside === 0)}`);
} else if (!pages) {
  out.push("## 값별 점검 (검증 1·2)", "", "| 이전 값 | 새 값 | 원본 건수 | 바뀐 횟수 | 남은 이전 값 | 판정 |", "|---|---|---|---|---|---|");
  for (const p of pairs) {
    const o = count(A, p.old), rem = count(B, p.old), added = count(B, p.new) - count(A, p.new);
    const contains = p.new.includes(p.old);
    const ok = (contains || rem === 0) && added === o && o > 0;
    out.push(`| ${p.old} | ${p.new} | ${o} | ${added} | ${rem}${contains ? " (새 값이 이전 값을 포함)" : ""} | ${mark(ok)} |`);
  }
} else {
  // 쪽 지정: 쪽 그림 글자로 쪽마다 센다
  const want = new Set();
  for (const part of pages.split(",")) { const [a, b] = part.split("-").map(Number); for (let p = a; p <= (b || a); p++) want.add(p); }
  const unent = s => s.replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&quot;/g, '"').replace(/&amp;/g, "&");
  const pageTexts = dir => fs.readdirSync(dir).filter(f => /^page_\d+\.svg$/.test(f)).sort()
    .map(f => [...fs.readFileSync(`${dir}/${f}`, "utf8").matchAll(/<text[^>]*>([^<]*)<\/text>/g)].map(m => unent(m[1])).join(""));
  const PA = pageTexts(`${tmp}/a/pages`), PB = pageTexts(`${tmp}/b/pages`);
  out.push(`## 쪽별 점검 (정한 쪽: ${[...want].join(", ")})`, "");
  out.push(`- 쪽 수: 원본 ${PA.length}, 결과 ${PB.length} — ${mark(PA.length === PB.length)}`, "");
  out.push("| 이전 값 → 새 값 | 쪽 | 원본 이전 값 | 결과 이전 값 | 원본 새 값 | 결과 새 값 | 판정 |", "|---|---|---|---|---|---|---|");
  for (const p of pairs) {
    let inWant = 0;
    PA.forEach((ta, i) => {
      const tb = PB[i] || "", pg = i + 1;
      const ao = count(ta, p.old), bo = count(tb, p.old), an = count(ta, p.new), bn = count(tb, p.new);
      let ok;
      if (want.has(pg)) { inWant += ao; ok = (p.new.includes(p.old) || bo === 0) && bn - an === ao; }
      else ok = bo === ao && bn === an;
      out.push(`| ${p.old} → ${p.new} | ${pg}${want.has(pg) ? " (정한 쪽)" : ""} | ${ao} | ${bo} | ${an} | ${bn} | ${mark(ok)} |`);
    });
    out.push(`| ${p.old} → ${p.new} | 정한 쪽 합계 | ${inWant} | | | | ${mark(inWant > 0)} |`);
  }
}

// 줄 단위: 달라진 줄은 반드시 "원본 줄에서 값만 바꾼 모양"이어야 한다
let extra = 0;
if (aL.length !== bL.length) extra = Math.abs(aL.length - bL.length) + 1;
else aL.forEach((l, i) => { if (l !== bL[i] && repl(l) !== bL[i]) extra++; });
if (!pages) { // 문서 전체(또는 제목 범위 안): 이전 값이 있는 줄은 모두 바뀌어야 한다
  aL.forEach((l, i) => { if (inR(i) && aL.length === bL.length && l === bL[i] && repl(l) !== l) extra++; });
}

const tl = t => t.split("\n").filter(l => l.startsWith("|")).length;
const ht = t => (t.match(/<table/g) || []).length;
out.push("", "## 표·서식 점검 (검증 5)", "", "| 항목 | 원본 | 결과 | 판정 |", "|---|---|---|---|");
out.push(`| 표 줄 수 | ${tl(A)} | ${tl(B)} | ${mark(tl(A) === tl(B))} |`);
out.push(`| 병합 표 수 | ${ht(A)} | ${ht(B)} | ${mark(ht(A) === ht(B))} |`);
out.push(`| 전체 줄 수 | ${aL.length} | ${bL.length} | ${mark(aL.length === bL.length)} |`);
out.push(`| 값 바꾸기로 설명되지 않는 줄 | - | ${extra} | ${mark(extra === 0)} |`);
if (log) {
  const L = fs.existsSync(log) ? fs.readFileSync(log, "utf8") : "";
  const m = L.match(/(\d+)개 변경 적용/);
  const applied = m ? Number(m[1]) : 0;
  const skips = L.split("\n").filter(l => l.includes("SKIP") && pairs.some(p => l.includes(p.old))).length;
  out.push(`| patch 적용 수 | - | ${applied} | ${mark(applied > 0)} |`);
  out.push(`| 이전 값이 들어 있는데 건너뛴(SKIP) 곳 | - | ${skips} | ${mark(skips === 0)} |`);
}
out.push(`| 결과 형식 (확장자 / 실제) | .${oext} | .${rext} / ${real} | ${mark(oext === rext && rext === real)} |`);

out.push("", "## 바뀐 줄 (검증 3 — 줄마다 잘못 바뀐 곳이 없는지 사람이 확인)", "");
let n = 0;
if (aL.length === bL.length) aL.forEach((l, i) => {
  if (l !== bL[i]) { n++; out.push(`- [ ] 줄 ${i + 1}`, `  - 전: ${l}`, `  - 후: ${bL[i]}`); }
});
else out.push("줄 수가 달라 줄 단위로 맞춰 볼 수 없음");
out.push("", `바뀐 줄 ${n}줄`);

out.unshift(`# 점검 결과 — ${fail ? "실패 있음" : "자동 점검 모두 통과"}`, "", `- 원본: ${oname}`, `- 결과: ${rname}`, ...(pages ? [`- 정한 쪽: ${pages}`] : []), ...(srange ? [`- 제목 범위: ${section}`] : []), "");
console.log(out.join("\n"));
process.exit(fail ? 1 : 0);
EOF
