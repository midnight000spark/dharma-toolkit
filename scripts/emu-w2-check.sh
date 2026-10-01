#!/usr/bin/env bash
# Живая проверка W2 (пакет warning-3b): «показать → выключить → шторка пуста».
#
# Зачем: W2 — отменённая полоса не снимала **показанное** уведомление
# (cancelRange чистил только pending). Блок C7 (critical-1) и фикс W2 снимают
# доставленное по журналу последнего плана и по перечню активных уведомлений
# платформы. Здесь это проверяется на живом устройстве, а не на фейке:
#   1) свежая установка, гранты, запуск → план поставлен (pending есть);
#   2) `emu-fire.sh --no-replan` доводит плановый будильник до показа;
#   3) приложение убивается БЕЗ очистки уведомлений (`am kill`, не force-stop:
#      force-stop сам снимает показанное — ложно-зелёный прогон);
#   4) уведомления «выключаются» строкой настроек в БД (enabled=0) — так же,
#      как после выключения пользователем;
#   5) перезапуск (триггер D-36 «старт приложения») перепланирует с пустым
#      планом: показанное обязано исчезнуть из `dumpsys notification`.
#
# Критерий зелёного: показ был и выжил kill, а после переплана его нет;
# pending-будильников пакета тоже нет (полоса пуста).
#
# Ловушки, на которых легко получить ложный результат:
#   - `am force-stop` снимает уведомления сам → используем HOME + `am kill`;
#   - часы emu-fire всегда возвращает (trap) — перезапуск после прогона идёт
#     на нормальных часах;
#   - `dumpsys notification` — только с `--noredact`, иначе содержимое скрыто
#     (но запись видна, поэтому проверка на отсутствие записи честная и так);
#   - пакеты/пути не хардкодятся: applicationId — из gradle, БД — путь
#     приложения в app_flutter (kAppDatabaseFileName).
#
# Использование:
#   scripts/emu-w2-check.sh            # полный прогон (переустановка в начале)
#   EMU_W2_SKIP_INSTALL=1 scripts/emu-w2-check.sh   # без переустановки
#   EMU_W2_APK=... scripts/emu-w2-check.sh          # другой APK (default debug)
#
# Переменные: EMU_SERIAL (default emulator-5554), EMU_W2_WAIT (default 90) —
# сколько секунд ждать план/переплан, EMU_W2_TAG — тег традиции (default: из
# practice_trackers, на свежей установке — первый пресет манифеста).
#
# Exit: 0 — сценарий пройден (показ был, после выключения и переплана пусто);
#       1 — сценарий не пройден (показ не состоялся/не снят);
#       2 — среда не готова; 64 — неверные аргументы.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GRADLE_FILE="$REPO_ROOT/android/app/build.gradle.kts"
EMU_SERIAL="${EMU_SERIAL:-emulator-5554}"
ADB_BIN="${ADB_BIN:-adb}"
APK="${EMU_W2_APK:-$REPO_ROOT/build/app/outputs/flutter-apk/app-debug.apk}"
WAIT="${EMU_W2_WAIT:-90}"
SKIP_INSTALL="${EMU_W2_SKIP_INSTALL:-0}"

die() { echo "emu-w2-check: $*" >&2; exit "${EMU_W2_EXIT:-1}"; }
envdie() { echo "emu-w2-check: $*" >&2; exit 2; }

command -v "$ADB_BIN" >/dev/null 2>&1 || envdie "adb не найден в PATH"

# applicationId — из gradle, не хардкод (как в emu-perms/emu-verify/emu-fire).
if [ -z "${APP_ID:-}" ]; then
  line=""
  while IFS= read -r l; do
    case "$l" in
      *applicationId*=*) line="$l"; break ;;
    esac
  done <"$GRADLE_FILE"
  [ -n "$line" ] || envdie "applicationId не найден в $GRADLE_FILE"
  line="${line#*=}"
  line="${line#"${line%%[![:space:]]*}"}"
  line="${line%"${line##*[![:space:]]}"}"
  line="${line#\"}"
  line="${line%\"}"
  APP_ID="$line"
fi

DB_FILE="/data/data/$APP_ID/app_flutter/dharma_toolkit.sqlite"

adb_s() { "$ADB_BIN" -s "$EMU_SERIAL" "$@"; }

# --- устройство ---
state=""
while read -r serial st _rest; do
  if [ "$serial" = "$EMU_SERIAL" ]; then state="$st"; break; fi
done <<<"$("$ADB_BIN" devices 2>/dev/null || true)"
[ "$state" = "device" ] || envdie "устройство $EMU_SERIAL не подключено (state='${state:-none}'); сначала scripts/emu.sh up"
booted="$(adb_s shell getprop sys.boot_completed 2>/dev/null | tr -d '\r\n ' || true)"
[ "$booted" = "1" ] || envdie "$EMU_SERIAL ещё не загружен"

# root нужен для sqlite3 по БД приложения и (косвенно) для kill-фолбэка.
"$ADB_BIN" -s "$EMU_SERIAL" root >/dev/null 2>&1 || true
"$ADB_BIN" -s "$EMU_SERIAL" wait-for-device >/dev/null 2>&1 || true
uid="$(adb_s shell id 2>/dev/null | tr -d '\r' || true)"
case "$uid" in
  uid=0*) : ;;
  *) envdie "adb root недоступен (id: ${uid:-<пусто>}) — правка БД невозможна" ;;
esac
adb_s shell "which sqlite3 >/dev/null" 2>/dev/null || envdie "на устройстве нет sqlite3"

# --- свежая установка и гранты ---
if [ "$SKIP_INSTALL" != "1" ]; then
  [ -f "$APK" ] || envdie "нет APK: $APK (соберите: flutter build apk --debug)"
  echo "--- установка ---"
  adb_s uninstall "$APP_ID" >/dev/null 2>&1 || true
  adb_s install "$APK" >/dev/null || die "adb install не удался"
fi

"$REPO_ROOT/scripts/emu-perms.sh" grant >/dev/null || die "emu-perms.sh grant не удался"
echo "--- гранты выданы (POST_NOTIFICATIONS + SCHEDULE_EXACT_ALARM) ---"

launch_app() {
  adb_s shell "monkey -p $APP_ID -c android.intent.category.LAUNCHER 1" >/dev/null 2>&1 || true
}

# Счётчик pending-будильников нашего пакета (та же выборка, что в emu-fire:
# RTC-строка содержит ScheduledNotificationReceiver; пакет — в контексте выше).
pending_count() {
  local alarms="$1" count=0 prev1="" prev2="" l ctx
  while IFS= read -r l; do
    case "$l" in
      *"type=RTC_"*)
        ctx="$prev1$prev2"
        case "$ctx" in
          *"$APP_ID"*)
            case "$ctx" in
              *"ScheduledNotificationReceiver"*) count=$((count + 1)) ;;
            esac
            ;;
        esac
        ;;
    esac
    prev2="$prev1"
    prev1="$l"
  done <<<"$alarms"
  echo "$count"
}

# Число записей уведомлений нашего пакета в дампе. Считаются только строки
# начала записи (`NotificationRecord(`) с нашим пакетом — как в emu-fire:
# `pkg=` встречается и в других местах дампа, а `grep -c` по подстроке даёт
# завышенное число, не различимое глазом.
shown_count() {
  awk -v pat="pkg=$APP_ID" '
    /NotificationRecord\(/ && index($0, pat) { n++ }
    END { print n + 0 }
  ' <<<"$1"
}

# id первой показанной записи пакета (для цитаты в логе).
shown_id() {
  awk -v pat="pkg=$APP_ID" '
    /NotificationRecord\(/ && index($0, pat) {
      if (match($0, /id=[0-9]+/)) { print substr($0, RSTART + 3, RLENGTH - 3); exit }
    }
  ' <<<"$1"
}

wait_for() { # wait_for <секунды> <описание> <команда...>; команда выводит "1" при успехе
  local limit="$1" what="$2"; shift 2
  local spent=0 ok=""
  while [ "$spent" -lt "$limit" ]; do
    ok="$("$@" 2>/dev/null || true)"
    if [ "$ok" = "1" ]; then return 0; fi
    sleep 3; spent=$((spent + 3))
  done
  echo "emu-w2-check: не дождались: $what (${limit}s)" >&2
  return 1
}

# --- 1. план поставлен ---
echo "--- запуск приложения ---"
launch_app
plan_ok() {
  local alarms; alarms="$(adb_s shell dumpsys alarm 2>/dev/null || true)"
  local n; n="$(pending_count "$alarms")"
  [ "${n:-0}" -gt 0 ] && echo 1 || true
}
wait_for "$WAIT" "pending-план уведомлений" plan_ok || die "план не поставлен — показывать нечего"
alarms_before="$(adb_s shell dumpsys alarm 2>/dev/null || true)"
echo "pending-записей до показа: $(pending_count "$alarms_before")"

# --- 2. показ ---
echo "--- emu-fire (показ планового напоминания) ---"
"$REPO_ROOT/scripts/emu-fire.sh" --no-replan || die "emu-fire не довёл напоминание до показа"
dump_shown="$(adb_s shell dumpsys notification --noredact 2>/dev/null || true)"
shown_before="$(shown_count "$dump_shown")"
[ "${shown_before:-0}" -gt 0 ] || die "после emu-fire записи пакета в шторке нет"
shown_id="$(shown_id "$dump_shown")"
echo "показ подтверждён: записей пакета в шторке — $shown_before (id=$shown_id)"

# --- 3. kill без очистки уведомлений ---
echo "--- HOME + am kill (показ обязан пережить) ---"
adb_s shell input keyevent KEYCODE_HOME >/dev/null 2>&1 || true
sleep 2
adb_s shell "am kill $APP_ID" >/dev/null 2>&1 || true
pid="$(adb_s shell pidof "$APP_ID" 2>/dev/null | tr -d '\r\n ' || true)"
if [ -n "$pid" ]; then
  # am kill не берёт «воспринимаемый» процесс — добиваем от root, уведомления
  # это не снимает (в отличие от force-stop).
  adb_s shell "kill -9 $pid" >/dev/null 2>&1 || true
  sleep 2
  pid="$(adb_s shell pidof "$APP_ID" 2>/dev/null | tr -d '\r\n ' || true)"
fi
[ -z "$pid" ] || die "процесс $APP_ID не убит (pid=$pid)"
dump_after_kill="$(adb_s shell dumpsys notification --noredact 2>/dev/null || true)"
shown_after_kill="$(shown_count "$dump_after_kill")"
[ "${shown_after_kill:-0}" -gt 0 ] || die "показ исчез сам после kill — сценарий не различает W2 (ложно-зелёный путь)"
echo "показ пережил kill: записей пакета — $shown_after_kill"

# --- 4. выключить уведомления (строка настроек, как после действия пользователя) ---
tag="${EMU_W2_TAG:-}"
if [ -z "$tag" ]; then
  # Активный тег: строка настроек, если есть, иначе — материализованные пресетом
  # трекеры (таблица practices, первый пресет манифеста на свежей установке).
  tag="$(adb_s shell "sqlite3 '$DB_FILE' \"SELECT tradition_tag FROM notification_settings LIMIT 1\"" 2>/dev/null | tr -d '\r\n ' || true)"
fi
if [ -z "$tag" ]; then
  tag="$(adb_s shell "sqlite3 '$DB_FILE' \"SELECT tradition_tag FROM practices LIMIT 1\"" 2>/dev/null | tr -d '\r\n ' || true)"
fi
[ -n "$tag" ] || die "не удалось определить tradition_tag (нет ни строки настроек, ни трекеров)"
echo "--- выключение: tradition_tag='$tag', enabled=0 ---"
adb_s shell "sqlite3 '$DB_FILE' \"INSERT INTO notification_settings (tradition_tag, enabled, hour, minute, updated_at) VALUES ('$tag', 0, 8, 0, strftime('%s','now')) ON CONFLICT(tradition_tag) DO UPDATE SET enabled=0, updated_at=strftime('%s','now');\"" >/dev/null \
  || die "sqlite3 не смог записать настройку"
enabled="$(adb_s shell "sqlite3 '$DB_FILE' \"SELECT enabled FROM notification_settings WHERE tradition_tag='$tag'\"" 2>/dev/null | tr -d '\r\n ' || true)"
[ "$enabled" = "0" ] || die "настройка не записалась (enabled='$enabled')"
echo "в БД: enabled=$enabled"

# --- 5. перезапуск → стартовый переплан пустым планом → шторка пуста ---
echo "--- перезапуск (триггер D-36 «старт приложения») ---"
launch_app
clean_ok() {
  local dump alarms n m
  dump="$(adb_s shell dumpsys notification --noredact 2>/dev/null || true)"
  m="$(shown_count "$dump")"
  alarms="$(adb_s shell dumpsys alarm 2>/dev/null || true)"
  n="$(pending_count "$alarms")"
  if [ "${m:-0}" -eq 0 ] && [ "${n:-0}" -eq 0 ]; then echo 1; fi
}
wait_for "$WAIT" "пустую шторку и пустую полосу" clean_ok || die "показанное уведомление или pending-план остались после выключения"

dump_after="$(adb_s shell dumpsys notification --noredact 2>/dev/null || true)"
alarms_after="$(adb_s shell dumpsys alarm 2>/dev/null || true)"
echo "--- итог ---"
echo "было: показано записей=$shown_before, pending=$(pending_count "$alarms_before")"
echo "стало: показано записей=$(shown_count "$dump_after"), pending=$(pending_count "$alarms_after")"
echo "сценарий W2 пройден: показ → выключение → старт → шторка пуста"
exit 0
