#!/usr/bin/env bash
# Статус GitHub Actions для последней ветки main (или переданного sha).
#
# Зачем (R-25): CI-зелёный — условие приёмки этапа (AGENT, «Сквозные правила»
# ROADMAP), а авторизованный доступ к API может быть недоступен агенту: ключ
# `gh` живёт в keyring и переживает отзыв PAT (инцидент F-41). Для публичного
# репозитория список ранов читается без токена — этот скрипт и есть такой
# обходной путь: он только читает, ничего не меняет и не печатает секретов.
#
# Пуск:  ./scripts/ci_status.sh [ref] [--steps]   (по умолчанию — HEAD)
#        --steps — дополнительно пошаговый список задач первого рана (для
#        диагностики красного CI: какой шаг положил сборку).
# Выход: 0 — все раны на sha завершены success; 1 — есть фейл/в работе/нет данных.
#
# Ограничения: без токена действует лимит анонимных запросов (60/ч на IP) и
# приватный репозиторий даст 404 — тогда нужен `gh auth login -h github.com`
# (интерактивно, только человеком).
set -uo pipefail

REPO="midnight000spark/dharma-toolkit"
SHOW_STEPS=0
ARGS=()
for a in "$@"; do
  case "$a" in
    --steps) SHOW_STEPS=1 ;;
    *) ARGS+=("$a") ;;
  esac
done
RAW="${ARGS[0]:-HEAD}"
# API GitHub принимает head_sha только полный (7-символьный короткий даёт
# пустой список), поэтому нормализуем через git; если git-дерева нет —
# оставляем как есть и надеемся на полный sha.
SHA=$(git rev-parse --verify --quiet "${RAW}^{commit}" 2>/dev/null || true)
[ -n "${SHA}" ] || SHA="${RAW}"

if [ -z "${SHA}" ]; then
  echo "ci_status: не удалось определить sha (не git-дерево?)" >&2
  exit 1
fi

HTTP=$(curl -s -o /tmp/ci_status_runs.$$ -w '%{http_code}' \
  "https://api.github.com/repos/${REPO}/actions/runs?head_sha=${SHA}&per_page=20")

if [ "${HTTP}" = "403" ] || [ "${HTTP}" = "429" ]; then
  echo "ci_status: HTTP ${HTTP} — исчерпан анонимный лимит API (60 запросов/ч на IP)" >&2
  echo "  подождать или авторизовать gh: gh auth login -h github.com" >&2
  rm -f /tmp/ci_status_runs.$$
  exit 1
fi

if [ "${HTTP}" != "200" ]; then
  echo "ci_status: API вернул HTTP ${HTTP} для ${REPO}" >&2
  echo "  404 — репозиторий приватный или недоступен без токена;" >&2
  echo "  решается человеком: gh auth login -h github.com" >&2
  rm -f /tmp/ci_status_runs.$$
  exit 1
fi

export CI_STATUS_REPO="${REPO}"
export CI_STATUS_STEPS="${SHOW_STEPS}"
python3 - "${SHA}" /tmp/ci_status_runs.$$ <<'PY'
import json
import os
import sys
import urllib.request

sha, path = sys.argv[1], sys.argv[2]
repo = os.environ["CI_STATUS_REPO"]
with open(path, encoding="utf-8") as fh:
    runs = json.load(fh).get("workflow_runs", [])

mine = [r for r in runs if r["head_sha"] == sha or r["head_sha"].startswith(sha[:7])]
if not mine:
    print(f"ci_status: ранов для {sha[:7]} не найдено (push не дошёл или ждём ~1 мин)")
    sys.exit(1)

rc = 0
for r in sorted(mine, key=lambda x: x["run_number"]):
    status, concl = r["status"], r["conclusion"]
    ok = status == "completed" and concl == "success"
    if not ok:
        rc = 1
    mark = "GREEN" if ok else f"{status}/{concl}"
    print(f"{mark:<18} #{r['run_number']} {r['name']} attempt={r['run_attempt']} "
          f"{r['created_at']}  {r['html_url']}")

if os.environ.get("CI_STATUS_STEPS") == "1":
    url = (f"https://api.github.com/repos/{repo}/actions/runs/"
           f"{sorted(mine, key=lambda x: x['run_number'])[-1]['id']}/jobs")
    with urllib.request.urlopen(url, timeout=30) as resp:
        jobs = json.load(resp).get("jobs", [])
    for j in jobs:
        print(f"  job {j['name']}: {j['status']}/{j['conclusion']}")
        for s in j.get("steps", []):
            flag = "  " if s["conclusion"] in ("success", "skipped") else "!!"
            print(f"   {flag}{s['number']:>2}. {s['name']:<32} {s['conclusion']}")
sys.exit(rc)
PY
code=$?
rm -f /tmp/ci_status_runs.$$
exit $code
