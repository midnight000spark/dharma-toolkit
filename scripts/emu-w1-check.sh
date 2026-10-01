#!/usr/bin/env bash
# Исполняемый чек-лист W1: рантайм-разрешение POST_NOTIFICATIONS (critical-1/08).
#
# Зачем: до W1 приложение не запрашивало разрешение само — приёмка этапа 6
# получалась в обход (`scripts/emu-perms.sh` выдавал грант через adb), и на
# свежей установке напоминания молча не показывались (review 19.09, W1).
# Сценарий ниже проходит БЕЗ emu-perms.sh: запрос обязан прийти от приложения
# при первом входе, отказ — оставить измеримые честные следы.
#
# Порядок прогона (ручные шаги 1–3 делаются глазами/adb; 4–5 проверяет скрипт):
#   1. adb uninstall <pkg> && adb install build/app/outputs/flutter-apk/app-release.apk
#   2. запустить приложение (am start) → платформенный диалог разрешения
#      «Allow … to send you notifications?» обязан появиться;
#   3. нажать «Don't allow» (отказ) или «Allow» (согласие);
#   4. scripts/emu-w1-check.sh --expect-denied   # или --expect-granted
#   5. ожидаемый повтор: exit 0.
#
# Что проверяется:
#   deny:  POST_NOTIFICATION=ignore / granted=false; процесс жив (не крах);
#          баннер «Напоминания не придут…» виден в uiautomator dump; в logcat
#          нет FATAL EXCEPTION.
#   allow: grant=true; баннера в дампе нет; процесс жив.
#
# Переменные:
#   EMU_SERIAL  — серийник (default: emulator-5554)
#   ADB_BIN     — adb (default: adb)
#   APP_ID      — пакет (default: applicationId из android/app/build.gradle.kts)
#
# Exit: 0 — состояние совпало с ожиданием; 1 — не совпало; 2 — среды нет.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GRADLE_FILE="$REPO_ROOT/android/app/build.gradle.kts"
EMU_SERIAL="${EMU_SERIAL:-emulator-5554}"
ADB_BIN="${ADB_BIN:-adb}"
MODE="${1:-print}"

die() { echo "emu-w1-check: $*" >&2; exit 2; }

case "$MODE" in
  --expect-denied|--expect-granted|print) : ;;
  *) die "неизвестный аргумент '$MODE' (ожидается: --expect-denied | --expect-granted)" ;;
esac

command -v "$ADB_BIN" >/dev/null 2>&1 || die "adb не найден в PATH"
[ -f "$GRADLE_FILE" ] || die "не найден $GRADLE_FILE"

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

# Устройство подключено и загружено.
state=""
while read -r serial st _rest; do
  if [ "$serial" = "$EMU_SERIAL" ]; then state="$st"; break; fi
done <<<"$("$ADB_BIN" devices 2>/dev/null || true)"
[ "$state" = "device" ] || die "устройство $EMU_SERIAL не подключено (state='${state:-none}')"

installed=""
while read -r p; do
  if [ "$p" = "package:$APP_ID" ]; then installed="yes"; break; fi
done <<<"$(adb_s shell pm list packages 2>/dev/null || true)"
[ "$installed" = "yes" ] || die "пакет $APP_ID не установлен"

# --- Состояние разрешения (appops + runtime-грант) ---
appops="$(adb_s shell cmd appops get "$APP_ID" POST_NOTIFICATION 2>/dev/null | tr -d '\r' || true)"
grant_line="$(adb_s shell dumpsys package "$APP_ID" 2>/dev/null | tr -d '\r' || true)"
granted="unknown"
case "$grant_line" in
  *"android.permission.POST_NOTIFICATIONS: granted=true"*) granted="true" ;;
  *"android.permission.POST_NOTIFICATIONS: granted=false"*) granted="false" ;;
esac

# --- Процесс жив? ---
pid="$(adb_s shell pidof "$APP_ID" 2>/dev/null | tr -d '\r\n ' || true)"

# --- Баннер в дампе окна (текст честного состояния) ---
adb_s shell uiautomator dump /sdcard/emu-w1-check.xml >/dev/null 2>&1 || true
ui="$(adb_s shell cat /sdcard/emu-w1-check.xml 2>/dev/null | tr -d '\r' || true)"
banner="нет"
case "$ui" in
  *"не придут"*) banner="есть" ;;
esac

# --- Краши в logcat ---
crashes="$(adb_s logcat -d 2>/dev/null | tr -d '\r' || true)"
fatal="нет"
case "$crashes" in
  *"FATAL EXCEPTION"*) fatal="есть" ;;
esac

echo "--- W1: разрешение на уведомления ($APP_ID) ---"
echo "appops:  ${appops:-<пусто>}"
echo "granted: $granted"
echo "pid:     ${pid:-<нет процесса>}"
echo "баннер:  $banner"
echo "краши:   $fatal"

case "$MODE" in
  --expect-denied)
    [ "$granted" = "false" ] || die "ожидался granted=false (отказ), получено '$granted'"
    [ -n "$pid" ] || die "процесс обязан быть жив после отказа (краха нет)"
    [ "$banner" = "есть" ] || die "баннер «Напоминания не придут…» не найден в дампе"
    [ "$fatal" = "нет" ] || die "в logcat есть FATAL EXCEPTION"
    echo "OK: отказ виден и честен (грант false, баннер, процесс жив)"
    ;;
  --expect-granted)
    [ "$granted" = "true" ] || die "ожидался granted=true (согласие), получено '$granted'"
    [ -n "$pid" ] || die "процесс обязан быть жив после согласия"
    [ "$banner" = "нет" ] || die "при выданном разрешении баннер не показывается"
    echo "OK: согласие принято, обещание напоминаний не ослаблено"
    ;;
  print)
    echo "(режим печати: проверки не выполнялись)"
    ;;
esac
