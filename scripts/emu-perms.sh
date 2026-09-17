#!/usr/bin/env bash
# Гранты разрешений для прогона уведомлений на эмуляторе (android-emu-0/C).
#
# Зачем: без грантов прогон упрётся в runtime-политики Android, а не в наш код.
#   - POST_NOTIFICATIONS (API 33+): runtime-разрешение на показ уведомлений.
#   - SCHEDULE_EXACT_ALARM (API 31+, ужесточено в 14): на API 34+ новым
#     приложениям запрещено по умолчанию, выдаётся через app-op (F-57, D-36).
#
# Использование:
#   scripts/emu-perms.sh            # выдать гранты (applicationId из gradle)
#   scripts/emu-perms.sh revoke     # отозвать (чистый прогон сценария)
#   APP_ID=... scripts/emu-perms.sh # явное переопределение (редко нужно)
#
# applicationId читается из android/app/build.gradle.kts, НЕ хардкодится.
#
# Формы команд (Tier-0):
#   - pm grant <pkg> android.permission.POST_NOTIFICATIONS — штатный для runtime.
#   - appops set --uid <pkg> SCHEDULE_EXACT_ALARM allow — uid-mode: `--uid`
#     в синтаксисе `appops set [--user <ID>] <[--uid] PACKAGE | UID> <OP> <MODE>`
#     подтверждён `adb shell appops help` на устройстве API 35; uid-режим
#     выбран потому, что security-связанные app-ops контролируются per-uid
#     (AOSP: frameworks/base/core/java/android/app/AppOps.md).
#   - Проверка: `appops get <pkg> SCHEDULE_EXACT_ALARM` -> allow (без --uid:
#     в синтаксисе `get` флага --uid нет).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GRADLE_FILE="$REPO_ROOT/android/app/build.gradle.kts"
EMU_SERIAL="${EMU_SERIAL:-emulator-5554}"
ADB_BIN="${ADB_BIN:-adb}"
MODE="${1:-grant}"

die() { echo "emu-perms: $*" >&2; exit 1; }

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
[ -n "$APP_ID" ] || die "applicationId пуст"

adb_s() { "$ADB_BIN" -s "$EMU_SERIAL" "$@"; }

# Устройство должно быть подключено и загружено.
state=""
while read -r serial st _rest; do
  if [ "$serial" = "$EMU_SERIAL" ]; then state="$st"; break; fi
done <<<"$("$ADB_BIN" devices 2>/dev/null || true)"
[ "$state" = "device" ] || die "устройство $EMU_SERIAL не подключено (state='${state:-none}'); сначала scripts/emu.sh up"

# Приложение обязано быть установлено — иначе appops/pm не найдут пакет.
installed=""
while read -r p; do
  if [ "$p" = "package:$APP_ID" ]; then installed="yes"; break; fi
done <<<"$(adb_s shell pm list packages 2>/dev/null || true)"
[ "$installed" = "yes" ] || die "пакет $APP_ID не установлен на $EMU_SERIAL (сначала: flutter install / adb install)"

api_level="$(adb_s shell getprop ro.build.version.sdk 2>/dev/null | tr -d '\r\n ' || true)"

case "$MODE" in
  grant)
    if [ "${api_level:-0}" -ge 33 ]; then
      adb_s shell pm grant "$APP_ID" android.permission.POST_NOTIFICATIONS
      echo "POST_NOTIFICATIONS: выдан"
    else
      echo "POST_NOTIFICATIONS: пропущен (API $api_level < 33 — разрешение не существует)"
    fi

    if [ "${api_level:-0}" -ge 31 ]; then
      adb_s shell appops set --uid "$APP_ID" SCHEDULE_EXACT_ALARM allow
      echo "SCHEDULE_EXACT_ALARM: allow (uid-mode)"
    else
      echo "SCHEDULE_EXACT_ALARM: пропущен (API $api_level < 31)"
    fi
    ;;
  revoke)
    if [ "${api_level:-0}" -ge 33 ]; then
      adb_s shell pm revoke "$APP_ID" android.permission.POST_NOTIFICATIONS || true
    fi
    if [ "${api_level:-0}" -ge 31 ]; then
      adb_s shell appops set --uid "$APP_ID" SCHEDULE_EXACT_ALARM default
      echo "SCHEDULE_EXACT_ALARM: default (отозван)"
    fi
    ;;
  *)
    die "неизвестный режим '$MODE' (ожидается: grant | revoke)"
    ;;
esac

echo "--- проверка (пакет $APP_ID, API $api_level) ---"
exact="$(adb_s shell appops get "$APP_ID" SCHEDULE_EXACT_ALARM 2>/dev/null | tr -d '\r' || true)"
echo "appops get SCHEDULE_EXACT_ALARM -> ${exact:-<пусто>}"

notif="$(adb_s shell dumpsys package "$APP_ID" 2>/dev/null || true)"
case "$notif" in
  *"android.permission.POST_NOTIFICATIONS: granted=true"*) echo "POST_NOTIFICATIONS -> granted=true" ;;
  *) echo "POST_NOTIFICATIONS -> НЕ подтверждён (granted=true не найден в dumpsys package)" ;;
esac

if [ "$MODE" = "grant" ]; then
  case "$exact" in
    *allow*) : ;;
    *) die "SCHEDULE_EXACT_ALARM не выставлен в allow ('${exact:-<пусто>}')" ;;
  esac
fi
