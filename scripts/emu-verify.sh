#!/usr/bin/env bash
# Доказательство pending-будильников напоминаний на устройстве (android-emu-0/D).
#
# Зачем: критерий Этапа 6 — «уведомление приходит». Linux-платформа планировать
# не умеет вообще (F-57), поэтому платформенное доказательство даёт только
# устройство: записи AlarmManager по нашему пакету в `dumpsys alarm`.
# Сам выстрел в 08:00 следующего дня здесь не ждём — это демо-харнес 6.3.
#
# Использование:
#   scripts/emu-verify.sh                 # проверить pending и показать времена
#   scripts/emu-verify.sh --expect-exact  # + требовать window=0 (грант выдан)
#   scripts/emu-verify.sh --expect-inexact # + требовать непустое окно (без гранта)
#
# Переменные:
#   EMU_SERIAL          — серийник (default: emulator-5554)
#   EMU_EXPECT_HHMM     — ожидаемое локальное время напоминаний (default: 08:00, D-36)
#   EMU_MIN_ALARMS      — минимум ожидаемых записей (default: 1)
#
# Exit: 0 — проверки пройдены; 1 — нет; 2 — не удалось получить данные.
#
# Проверки сравнивают строки, полученные в переменные: конвейер с `grep -q`
# под `set -o pipefail` даёт ложный отрицательный результат (источник получает
# SIGPIPE на первом совпадении) — см. scripts/emu.sh.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GRADLE_FILE="$REPO_ROOT/android/app/build.gradle.kts"
EMU_SERIAL="${EMU_SERIAL:-emulator-5554}"
ADB_BIN="${ADB_BIN:-adb}"
EXPECT_HHMM="${EMU_EXPECT_HHMM:-08:00}"
MIN_ALARMS="${EMU_MIN_ALARMS:-1}"
EXPECT_MODE="any"

for arg in "$@"; do
  case "$arg" in
    --expect-exact) EXPECT_MODE="exact" ;;
    --expect-inexact) EXPECT_MODE="inexact" ;;
    *) echo "emu-verify: неизвестный аргумент '$arg'" >&2; exit 64 ;;
  esac
done

die() { echo "emu-verify: $*" >&2; exit 1; }

command -v "$ADB_BIN" >/dev/null 2>&1 || die "adb не найден в PATH"

# applicationId — из gradle, не хардкод.
if [ -z "${APP_ID:-}" ]; then
  line=""
  while IFS= read -r l; do
    case "$l" in
      *applicationId*=*) line="$l"; break ;;
    esac
  done <"$GRADLE_FILE"
  [ -n "$line" ] || die "applicationId не найден в $GRADLE_FILE"
  line="${line#*=}"
  line="${line#"${line%%[![:space:]]*}"}"
  line="${line%"${line##*[![:space:]]}"}"
  line="${line#\"}"
  line="${line%\"}"
  APP_ID="$line"
fi

adb_s() { "$ADB_BIN" -s "$EMU_SERIAL" "$@"; }

api_level="$(adb_s shell getprop ro.build.version.sdk 2>/dev/null | tr -d '\r\n ' || true)"
exact_grant="$(adb_s shell appops get "$APP_ID" SCHEDULE_EXACT_ALARM 2>/dev/null | tr -d '\r' || true)"

dump="$(adb_s shell dumpsys alarm 2>/dev/null || true)"
[ -n "$dump" ] || die "пустой dumpsys alarm (устройство $EMU_SERIAL подключено?)"

echo "Пакет: $APP_ID (API $api_level, устройство $EMU_SERIAL)"
case "$exact_grant" in
  *allow*) echo "SCHEDULE_EXACT_ALARM: allow (exact доступен)" ;;
  *) echo "SCHEDULE_EXACT_ALARM: НЕ выдан (планировщик обязан уйти в inexact)" ;;
esac
echo "Ожидание: время $EXPECT_HHMM локально, минимум записей $MIN_ALARMS"
echo "---"

count=0
bad_time=0
exact_count=0
inexact_count=0
prev1=""
prev2=""

# Идём по строкам dumpsys. Структура блока AlarmManager:
#   RTC_WAKEUP #43: Alarm{... <pkg>}            <- заголовок с пакетом
#     tag=*walarm*:<pkg>/...ScheduledNotificationReceiver   <- наш тег
#     type=RTC_WAKEUP origWhen=... window=...    <- детали (время, точность)
# Поэтому строка деталей опознаётся по ДВУМ предыдущим строкам: пакет + наш
# ресивер. Проверка по строке деталей не сработала бы (ни пакета, ни тега там
# нет) — именно на этом спотыкалась первая версия скрипта.
while IFS= read -r l; do
  case "$l" in
    *"type=RTC_"*)
      ctx="$prev1$prev2"
      case "$ctx" in
        *"$APP_ID"*)
          case "$ctx" in
            *"ScheduledNotificationReceiver"*)
              count=$((count + 1))
              # origWhen содержит пробел внутри значения ("2026-09-21 08:00:00.000"),
              # поэтому берём подстроку между меткой и следующим полем, а не токен.
              after="$l"
              when=""
              window=""
              case "$after" in
                *origWhen=*) after="${after#*origWhen=}"; when="${after%% window=*}" ;;
              esac
              case "$l" in
                *window=*) w="${l#*window=}"; window="${w%% *}" ;;
              esac
              echo "[$count] origWhen=$when window=$window"
              case "$when" in
                *" $EXPECT_HHMM:"*) ;;
                *) bad_time=$((bad_time + 1)) ;;
              esac
              if [ "$window" = "0" ]; then
                exact_count=$((exact_count + 1))
              else
                inexact_count=$((inexact_count + 1))
              fi
              ;;
          esac
          ;;
      esac
      ;;
  esac
  prev2="$prev1"
  prev1="$l"
done <<<"$dump"

echo "---"
echo "Записей по пакету: $count (exact: $exact_count, inexact: $inexact_count)"
echo "Несовпадений времени $EXPECT_HHMM: $bad_time"

fail=0
[ "$count" -ge "$MIN_ALARMS" ] || { echo "FAIL: записей $count < $MIN_ALARMS"; fail=1; }
[ "$bad_time" -eq 0 ] || { echo "FAIL: $bad_time записей не в $EXPECT_HHMM"; fail=1; }

case "$EXPECT_MODE" in
  exact)
    [ "$inexact_count" -eq 0 ] && [ "$exact_count" -ge "$MIN_ALARMS" ] || {
      echo "FAIL: ожидались exact (window=0), получено exact=$exact_count inexact=$inexact_count"; fail=1; }
    ;;
  inexact)
    [ "$exact_count" -eq 0 ] && [ "$inexact_count" -ge "$MIN_ALARMS" ] || {
      echo "FAIL: ожидались inexact, получено exact=$exact_count inexact=$inexact_count"; fail=1; }
    ;;
  any) ;;
esac

[ "$fail" -eq 0 ] || exit 1
echo "OK: pending-будильники напоминаний на месте"
