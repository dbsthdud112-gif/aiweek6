#!/usr/bin/env bash
# CLAUDE.md 규칙 확인: 동의한 수정이 01·02에 모두 반영됐는지, out/ 결과물을 어떻게 만들었는지 적혀 있는지
# 사용법: bash check_rules.sh   (raw/는 읽지 않음)

cd "$(dirname "$0")" || exit 2
PP="01_페인포인트.md"
PLAN="02_기획안.md"
fail=0

section() { # 파일 $1에서 "## $2" 제목부터 다음 "## " 제목 전까지
  awk -v h="## $2" '$0 == h {f=1; next} /^## / {f=0} f' "$1"
}

echo "[A] 01 검증기준의 숫자 기준이 02 검증에도 있는가"
plan_check="$(section "$PLAN" "검증")"
a_fail=0
while IFS= read -r line; do
  case "$line" in *확인필요*|"") continue ;; esac
  while IFS= read -r tok; do
    [ -z "$tok" ] && continue
    if printf '%s\n' "$plan_check" | grep -qF -- "$tok"; then
      echo "  통과: '$tok'"
    else
      echo "  실패: '$tok' 이(가) 02 › 검증에 없음  ← $line"
      a_fail=1
    fi
  done < <(printf '%s\n' "$line" | grep -oE '[0-9]+(분|시간) (이하|이내)|[0-9]+건')
done < <(section "$PP" "검증기준")
[ "$a_fail" -eq 1 ] && fail=1

echo "[B] 01·02에 미반영 표시가 남아 있지 않은가"
if grep -nE '아직 반영하지 않았|반영 전|반영 예정' "$PP" "$PLAN"; then
  echo "  실패: 위 줄에 미반영 표시가 남아 있음"
  fail=1
else
  echo "  통과: 미반영 표시 0건"
fi

echo "[C] out/ 결과물을 어떻게 만들었는지 검증결과에 적혀 있는가"
results="$(ls out/계획서_*.md 2>/dev/null)"
if [ -z "$results" ]; then
  echo "  해당 없음: out/에 결과 파일이 없음"
else
  reports="$(ls out/검증결과_*.md 2>/dev/null)"
  if [ -z "$reports" ]; then
    echo "  실패: 결과 파일은 있는데 out/검증결과_*.md 가 없음"
    fail=1
  else
    for r in $reports; do
      if grep -qE '^- 실행 방법:.*내려받기' "$r"; then
        echo "  통과: $r 에 '실행 방법' 줄이 있고 내려받기 방식이 적혀 있음"
      else
        echo "  실패: $r 에 '- 실행 방법: …내려받기…' 줄이 없음"
        fail=1
      fi
    done
  fi
fi

echo
if [ "$fail" -eq 0 ]; then echo "결과: 모두 통과"; else echo "결과: 실패 있음"; fi
exit "$fail"
