#!/usr/bin/env python3
"""Генератор тест-векторов тибетского календаря (Пхугпа) из dorjeduck/tibcal.

Ground truth пакета 5a: tibcal (MIT; алгоритм Сванте Янсона, Пхугпа эпохи
E806) — см. F-18/F-43. Скрипт остаётся в репозитории для воспроизводимости:
на фиксированном коммите tibcal вывод детерминирован (метка времени не
пишется).

Использование:
    TIBCAL_DIR=/path/to/tibcal/public python3 scripts/gen_tibcal_vectors.py

Выход: test/fixtures/tibcal_vectors.json
  - g2t: григорианская -> тибетская для каждого дня 2024 и 2026 годов;
  - t2g: обратный ход каждой полученной тибетской даты (round-trip);
  - losar: Лосары (месяц 1, день 1) тибетских годов 2023..2027 + обратный g2t;
  - skipped_days: пропущенные дни (разрыв нумерации внутри месяца в потоке
    g2t) с григорианскими якорями;
  - doubled_days: двойные дни (повтор номера, первый — с leapDay=true).
"""

from __future__ import annotations

import functools
import json
import os
import platform
import subprocess
import sys
from datetime import date, timedelta

TIBCAL_DIR = os.environ.get(
    "TIBCAL_DIR", "/tmp/opencode/spike5a/tibcal/public")
sys.path.insert(0, TIBCAL_DIR)

import tibetan_calendar as tc  # noqa: E402
from tibetan_calendar import TibetanDate, TibetanTradition  # noqa: E402

# Кэширование построения месяцев: g2t для каждого дня перебирает трёхлетнее
# окно, однотипные месяцы строятся повторно. Ускоряет генерацию на порядки.
tc._build_month = functools.lru_cache(maxsize=None)(tc._build_month)
tc._month_instances = functools.lru_cache(maxsize=None)(tc._month_instances)

TRADITION = TibetanTradition.PHUGPA

# Диапазоны полного потока g2t (2024 — высокосный, 2026 — текущий).
RANGES = [
    (date(2024, 1, 1), date(2024, 12, 31)),
    (date(2026, 1, 1), date(2026, 12, 31)),
]
LOSAR_YEARS = range(2023, 2028)

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_PATH = os.path.join(REPO_ROOT, "test", "fixtures", "tibcal_vectors.json")


def tib_payload(td: TibetanDate) -> dict:
    return {
        "year": td.year,
        "month": td.month,
        "leapMonth": td.is_leap_month,
        "day": td.day,
        "leapDay": td.is_leap_day,
    }


def tib_key(payload: dict) -> tuple:
    return (payload["year"], payload["month"], payload["leapMonth"],
            payload["day"], payload["leapDay"])


def tibcal_commit() -> str:
    root = os.path.dirname(TIBCAL_DIR)
    try:
        return subprocess.run(
            ["git", "-C", root, "rev-parse", "HEAD"],
            capture_output=True, text=True, check=True).stdout.strip()
    except Exception:
        return "unknown"


def main() -> None:
    # --- g2t: каждый день диапазонов -------------------------------------
    g2t = []
    for start, end in RANGES:
        d = start
        while d <= end:
            td = tc.gregorian_to_tibetan(d, TRADITION)
            assert td.gregorian == d and not td.is_skipped, (d, td)
            g2t.append({"gregorian": d.isoformat(), "tibetan": tib_payload(td)})
            d += timedelta(days=1)

    # --- t2g: обратный ход каждой уникальной полученной тибетской даты ---
    t2g = []
    seen: set[tuple] = set()
    for e in g2t:
        key = tib_key(e["tibetan"])
        if key in seen:
            continue
        seen.add(key)
        req = TibetanDate(key[0], key[1], key[2], key[3], key[4],
                          False, None, 0)
        g = tc.tibetan_to_gregorian(req, TRADITION)
        assert g.isoformat() == e["gregorian"], ("round-trip tibcal", req, g, e)
        t2g.append({"tibetan": e["tibetan"], "gregorian": g.isoformat()})

    # --- Лосары: t2g (y, 1, 1) + обратный g2t ----------------------------
    losar = []
    for y in LOSAR_YEARS:
        req = TibetanDate(y, 1, False, 1, False, False, None, 0)
        g = tc.tibetan_to_gregorian(req, TRADITION)
        back = tc.gregorian_to_tibetan(g, TRADITION)
        assert tib_payload(back) == {"year": y, "month": 1, "leapMonth": False,
                                     "day": 1, "leapDay": False}, \
            ("losar round-trip", y, back)
        losar.append({
            "tibetanYear": y,
            "gregorian": g.isoformat(),
            "g2tBack": tib_payload(back),
        })

    # --- аномалии из потока g2t -------------------------------------------
    skipped = []
    doubled = []
    prev = None
    for e in g2t:
        t = e["tibetan"]
        if prev is not None:
            p = prev["tibetan"]
            same_block = (t["year"], t["month"], t["leapMonth"]) == \
                         (p["year"], p["month"], p["leapMonth"])
            if same_block:
                if t["day"] == p["day"]:
                    # Дублирование: первая встреча — leapDay, вторая — обычная.
                    assert p["leapDay"] is True and t["leapDay"] is False, \
                        ("unexpected doubling", prev, e)
                    doubled.append({
                        "year": t["year"], "month": t["month"],
                        "leapMonth": t["leapMonth"], "day": t["day"],
                        "leapDate": prev["gregorian"],
                        "regularDate": e["gregorian"],
                    })
                elif t["day"] - p["day"] >= 2:
                    skipped.append({
                        "year": t["year"], "month": t["month"],
                        "leapMonth": t["leapMonth"],
                        "missingDays": list(range(p["day"] + 1, t["day"])),
                        "before": {"gregorian": prev["gregorian"],
                                   "day": p["day"]},
                        "after": {"gregorian": e["gregorian"], "day": t["day"]},
                    })
        prev = e

    assert len(skipped) >= 3, f"мало пропущенных дней: {len(skipped)}"
    assert len(doubled) >= 3, f"мало двойных дней: {len(doubled)}"

    # Прогон t2g для пропущенного дня обязан быть невозможным (ожидаем
    # ValueError в tibcal — это семантика, которую портирует наш порт).
    skip_check = None
    if skipped:
        s = skipped[0]
        req = TibetanDate(s["year"], s["month"], s["leapMonth"],
                          s["missingDays"][0], False, True, None, 0)
        try:
            tc.tibetan_to_gregorian(req, TRADITION)
            raise AssertionError("skipped day unexpectedly convertible")
        except ValueError as exc:
            skip_check = str(exc)

    vectors = {
        "meta": {
            "generator": "scripts/gen_tibcal_vectors.py",
            "source": "dorjeduck/tibcal (MIT, Phugpa E806, Janson)",
            "tibcal_commit": tibcal_commit(),
            "python_version": platform.python_version(),
            "tradition": "phugpa",
            "ranges": [f"{a.isoformat()}..{b.isoformat()}"
                       for a, b in RANGES],
            "counts": {
                "g2t": len(g2t),
                "t2g": len(t2g),
                "losar": len(losar),
                "skipped": len(skipped),
                "doubled": len(doubled),
            },
            "skipped_t2g_raises": skip_check,
        },
        "g2t": g2t,
        "t2g": t2g,
        "losar": losar,
        "skipped_days": skipped,
        "doubled_days": doubled,
    }

    os.makedirs(os.path.dirname(OUT_PATH), exist_ok=True)
    with open(OUT_PATH, "w", encoding="utf-8") as fh:
        json.dump(vectors, fh, ensure_ascii=False, indent=1, sort_keys=False)
        fh.write("\n")
    print(f"written {OUT_PATH}: g2t={len(g2t)} t2g={len(t2g)} "
          f"losar={len(losar)} skipped={len(skipped)} doubled={len(doubled)}")


if __name__ == "__main__":
    main()
