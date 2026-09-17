#!/usr/bin/env bash
# check_docs.sh — linkcheck документации (enforcement правила «устаревшая ссылка = баг документа»).
#
# Проверяет по отслеживаемым git markdown-файлам:
#   1) цели внутренних markdown-ссылок [..](path[#anchor]) существуют;
#   2) якоря #anchor резолвятся в целевом .md (GitHub-slug заголовка, <a id="..">, {#..});
#   3) обратные указатели `docs/...md` и `тело: docs/...#anchor` не слепые;
#   4) ссылки §N резолвятся в заголовок «N.» актуального БФТ (для БФТ — в нём самом).
#
# Exit 0 = чисто, exit 1 = есть находки. Скрипт read-only, ничего не пишет.
# Аттестован по уроку 1 (I-8): посадка битой ссылки → красный, снятие → зелёный.
set -euo pipefail

root="$(git rev-parse --show-toplevel)"
cd "$root"

python3 - <<'PY'
import os
import re
import subprocess
import sys

FILES = subprocess.check_output(["git", "ls-files", "*.md"], text=True).split()
if not FILES:
    print("check_docs: PASSED (0 files)")
    sys.exit(0)

# Актуальный БФТ — файл с наибольшей версией (конвенция «файл-на-версию»).
def bft_key(path):
    m = re.search(r"BFT-v(\d+)\.(\d+)\.md$", path)
    return (int(m.group(1)), int(m.group(2))) if m else (-1, -1)

bft_files = [f for f in FILES if bft_key(f) != (-1, -1)]
latest_bft = max(bft_files, key=bft_key) if bft_files else None


def strip_fences(text):
    """Убирает ```...``` блоки, чтобы примеры внутри них не считались ссылками."""
    return re.sub(r"```.*?```", "", text, flags=re.S)


def anchors_of(path):
    anchors = set()
    try:
        text = open(path, encoding="utf-8").read()
    except OSError:
        return anchors
    for m in re.finditer(r'<a\s+[^>]*?(?:id|name)="([^"]+)"', text, flags=re.I):
        anchors.add(m.group(1))
    for m in re.finditer(r"\{#([^}]+)\}", text):
        anchors.add(m.group(1))
    for line in text.splitlines():
        if re.match(r"^#{1,6} ", line):
            h = line.lstrip("#").strip().replace("**", "").replace("`", "")
            h = h.lower()
            h = re.sub(r"[^\w\- ]", "", h, flags=re.UNICODE)
            h = h.strip().replace(" ", "-")
            if h:
                anchors.add(h)
    return anchors


_anchor_cache = {}


def anchor_set(path):
    if path not in _anchor_cache:
        _anchor_cache[path] = anchors_of(path)
    return _anchor_cache[path]


def heading_for_section(path, n):
    try:
        text = open(path, encoding="utf-8").read()
    except OSError:
        return False
    # Заголовки БФТ: «## **13\. Известные риски...**» (номер экранирован точкой).
    return bool(re.search(r"^#{1,6}\s+\*\*" + re.escape(n) + r"\\?\.", text, re.M)) or bool(
        re.search(r"^#{1,6}\s+.*?\b" + re.escape(n) + r"\.\s", text, re.M)
    )


errors = []
checked_refs = 0


def check_ref(src, raw, kind):
    """Проверяет одну ссылку/указатель. raw — без обратных кавычек."""
    global checked_refs
    ref = raw.strip().strip("`").rstrip(".,;)")
    if not ref or ref.startswith(("http://", "https://", "mailto:", "tel:")):
        return
    if ref.startswith("#"):
        checked_refs += 1
        if ref[1:] not in anchor_set(src):
            errors.append(f"{src}: [{kind}] якорь {ref} не найден в самом файле")
        return
    path, _, anchor = ref.partition("#")
    path = path.strip()
    if not path:
        return
    checked_refs += 1
    src_dir = os.path.dirname(src)
    candidates = []
    if os.path.isabs(path):
        candidates.append(path.lstrip("/"))
    else:
        if src_dir:
            candidates.append(os.path.normpath(os.path.join(src_dir, path)))
        candidates.append(os.path.normpath(path))
    resolved = next((c for c in candidates if os.path.exists(c)), None)
    if resolved is None:
        errors.append(f"{src}: [{kind}] цель не найдена: {ref}")
        return
    if anchor and resolved.endswith(".md") and os.path.isfile(resolved):
        if anchor not in anchor_set(resolved):
            errors.append(f"{src}: [{kind}] якорь #{anchor} не найден в {resolved}")


link_re = re.compile(r"!?\[[^\]]*\]\(([^)\s]+)(?:\s+\"[^\"]*\")?\)")

for f in FILES:
    text = open(f, encoding="utf-8").read()
    scan = strip_fences(text)
    # 1) markdown-ссылки
    for m in link_re.finditer(scan):
        check_ref(f, m.group(1), "link")
    # 2) обратные указатели в кавычках на path/*.md (только пути со слешем)
    #    Токен с пробелом указателем не является: это пример команды или проза,
    #    случайно оканчивающаяся на «.md» (`firecrawl parse ./file.pdf -o out.md`).
    #    Путь-указатель пробелов не содержит — эвристика сужена в 6.4 после
    #    ложного красного на скилле (аттестация: пробный токен с пробелом —
    #    зелёный, настоящая отсутствующая цель — красный).
    for m in re.finditer(r"`([^`\n]+?\.md(?:#[^`\n]*)?)`", text):
        token = m.group(1)
        if "/" not in token or any(c in token for c in "*<>{}…"):
            continue
        if re.search(r"\s", token):
            continue
        check_ref(f, token, "path")
    # 3) указатели «тело: ...»
    for m in re.finditer(r"тело:\s*([^\s,;)]+)", text):
        check_ref(f, m.group(1), "тело")
    # 4) ссылки §N
    for m in re.finditer(r"§\s*(\d+)", text):
        n = m.group(1)
        checked_refs += 1
        candidates = [f] if bft_key(f) != (-1, -1) else []
        if latest_bft and latest_bft not in candidates:
            candidates.append(latest_bft)
        if not any(heading_for_section(c, n) for c in candidates):
            target = f if bft_key(f) != (-1, -1) else (latest_bft or "-")
            errors.append(f"{f}: [§] раздел §{n} не найден в {target}")

if errors:
    for e in errors:
        print(f"FAIL {e}")
    print(f"check_docs: FAILED ({len(errors)} problem(s), {len(FILES)} files, {checked_refs} refs)")
    sys.exit(1)

print(f"check_docs: PASSED ({len(FILES)} files, {checked_refs} refs)")
PY
