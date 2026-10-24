#!/usr/bin/env bash
# 한글 계획서 값 바꾸기 — Claude 없이 터미널에서 직접 돌리는 명령. 문서 내용이 Claude에게 가지 않는다.
#
# 사용법 (이 폴더에서):
#   bash 값바꾸기.sh raw/계획서.hwpx "2025년=>2026년" "5,000만 원=>6,000만 원"
#   bash 값바꾸기.sh -p 1 raw/계획서.hwpx "2025년=>2026년"              # 1쪽만 (2-4, 1,3 도 가능)
#   bash 값바꾸기.sh -s "2. 사업 개요" raw/계획서.hwpx "2025년=>2026년"   # 제목 범위만
#
# 결과: out/계획서_날짜[_범위].<확장자>, out/계획서_날짜[_범위]_변경목록.md
# 점검이 실패하면 결과 파일은 out/에 두지 않고, 이유만 out/…_점검실패.md 에 남긴다.
# 종료 코드: 0 성공, 1 실패(점검 실패 포함), 2 사용법 오류

cd "$(dirname "$0")" || exit 2
S=".claude/skills/계획서-값바꾸기"

usage() {
  sed -n '4,7p' "$0" | sed 's/^# \{0,3\}//' >&2
  exit 2
}

pages=""; section=""
while [ $# -gt 0 ]; do
  case "$1" in
    -p) pages="$2"; shift 2 ;;
    -s) section="$2"; shift 2 ;;
    -h|--help) usage ;;
    *) break ;;
  esac
done
[ $# -lt 2 ] && usage
[ -n "$pages" ] && [ -n "$section" ] && { echo "-p 와 -s 는 같이 쓸 수 없어요." >&2; exit 2; }
src="$1"; shift
[ -f "$src" ] || { echo "파일이 없어요: $src" >&2; exit 2; }
ext="${src##*.}"
case "$ext" in hwp|hwpx) ;; *) echo "한글 파일(.hwp/.hwpx)만 돼요: $src" >&2; exit 2 ;; esac
for a in "$@"; do case "$a" in ?*"=>"*) ;; *) echo "바꿀 값은 \"이전=>새\" 모양으로 적어 주세요: $a" >&2; exit 2 ;; esac; done

kd() { npx -y kordoc@^4 "$@"; }
hash_before="$(sha256sum "$src" | cut -d' ' -f1)"
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
cp "$src" "$W/원본.$ext"

echo "1/5 읽는 중…"
kd "$W/원본.$ext" -o "$W/편집.md" >/dev/null 2>&1 || { echo "파일을 읽지 못했어요 (암호가 걸린 파일일 수 있어요)." >&2; exit 1; }

echo "2/5 값 바꾸는 중…"
if [ -n "$pages" ]; then
  kd render "$W/원본.$ext" -d "$W/pages" --silent >/dev/null 2>&1 || { echo "쪽 그림을 그리지 못했어요." >&2; exit 1; }
  node "$S/page_replace.mjs" "$W/편집.md" "$W/pages" "$pages" "$W/편집.md" "$@" > "$W/replace.log" 2>&1 \
    || { grep -E '쪽을 찾지 못함|문서는|잘못된' "$W/replace.log" | head -5; echo "→ 바꾸지 않고 멈췄어요. 쪽 경계에 걸친 문단일 수 있어요." >&2; exit 1; }
elif [ -n "$section" ]; then
  node "$S/section_replace.mjs" "$W/편집.md" "$section" "$W/편집.md" "$@" > "$W/replace.log" 2>&1 \
    || { cat "$W/replace.log"; echo "→ 바꾸지 않고 멈췄어요. 위 목록에서 제목을 골라 -s 에 다시 적어 주세요." >&2; exit 1; }
else
  node "$S/replace.mjs" "$W/편집.md" "$W/편집.md" "$@" > "$W/replace.log" 2>&1 || { cat "$W/replace.log"; exit 1; }
fi

echo "3/5 한글 파일에 반영하는 중…"
kd patch "$W/원본.$ext" "$W/편집.md" -o "$W/결과.$ext" > "$W/patch.log" 2>&1
[ -f "$W/결과.$ext" ] || { echo "한글 파일에 반영하지 못했어요." >&2; exit 1; }
if [ "$ext" = "hwpx" ]; then
  kd validate "$W/결과.hwpx" > "$W/validate.log" 2>&1 || { echo "결과 파일 구조 검사에 실패했어요." >&2; exit 1; }
fi

echo "4/5 점검하는 중…"
opt=()
[ -n "$pages" ] && opt=(-p "$pages")
[ -n "$section" ] && opt=(-s "$section")
bash "$S/check.sh" -l "$W/patch.log" "${opt[@]}" "$W/원본.$ext" "$W/결과.$ext" "$@" > "$W/점검.md"
ok=$?

echo "5/5 저장하는 중…"
mkdir -p out
d="$(date +%F)"
tag=""
[ -n "$pages" ] && tag="_${pages}쪽"
if [ -n "$section" ]; then
  t="$(printf '%s' "$section" | sed -E 's/[0-9]+\.//g; s/[[:space:]]+//g; s/^~/처음~/; s/~$/~끝/; s/~/-/g; s#[\\/:*?"<>|]##g')"
  tag="_${t}"
fi
base="out/계획서_${d}${tag}"; n=""
while [ -e "${base}${n}.$ext" ] || [ -e "${base}${n}_변경목록.md" ] || [ -e "${base}${n}_점검실패.md" ]; do
  n="_v$(( ${n#_v} + 1 ))"; [ "$n" = "_v1" ] && n="_v2"
done
base="${base}${n}"

head_lines="- 원본: $src"$'\n'"- 만든 날: $d"$'\n'"- 바꾼 값: $*"
if [ $ok -ne 0 ]; then
  { sed -n '1p' "$W/점검.md"; echo; printf '%s\n' "$head_lines"; sed -n '2,$p' "$W/점검.md" | sed '/^- 원본: /d; /^- 결과: /d'; } > "${base}_점검실패.md"
  echo
  echo "점검 실패 — 결과 파일은 저장하지 않았어요."
  echo "이유: ${base}_점검실패.md"
  exit 1
fi
cp "$W/결과.$ext" "${base}.$ext"
{ sed -n '1p' "$W/점검.md"; echo; printf '%s\n' "- 결과: ${base}.$ext" "$head_lines"; sed -n '2,$p' "$W/점검.md" | sed '/^- 원본: /d; /^- 결과: /d'; } > "${base}_변경목록.md"

[ "$(sha256sum "$src" | cut -d' ' -f1)" = "$hash_before" ] || { echo "경고: 원본이 바뀌었어요! $src" >&2; exit 1; }

echo
echo "자동 점검 모두 통과 ($(grep -c '^- \[ \]' "${base}_변경목록.md")줄 바뀜, 원본은 그대로)"
echo "결과:        ${base}.$ext"
echo "바뀐 곳 목록: ${base}_변경목록.md  ← 줄마다 잘못 바뀐 곳이 없는지 확인해 주세요"
