#!/usr/bin/env bash
# Живой выстрел напоминания на эмуляторе (блок A пакета 6.3).
#
# Зачем: критерий Этапа 6 — «уведомление приходит». `emu-verify.sh` доказывает
# лишь наличие pending-будильников; здесь будильник доводится до срабатывания:
# стенные часы эмулятора переводятся к моменту плана, а показ проверяется в
# `dumpsys notification`.
#
# Использование:
#   scripts/emu-fire.sh                       # ближайший pending → 07:59 → ждём 08:00
#   scripts/emu-fire.sh --expect-title "10-й день тибетского месяца"
#   EMU_FIRE_LEAD=90 scripts/emu-fire.sh      # иная проходка перед моментом
#   scripts/emu-fire.sh --no-replan           # не перезапускать приложение после прогона
#
# Переменные:
#   EMU_SERIAL       — серийник (default: emulator-5554)
#   EMU_EXPECT_HHMM  — локальное время напоминаний (default: 08:00, D-36)
#   EMU_FIRE_LEAD    — на сколько секунд до момента ставить часы (default: 60)
#   EMU_FIRE_TIMEOUT — сколько секунд ждать показ (default: 180)
#
# Exit: 0 — уведомление сработало и найдено в `dumpsys notification`;
#       1 — срабатывания нет (нет pending / не дождались);
#       2 — среда не готова (нет adb/устройства, не удалось перевести часы);
#      64 — неверные аргументы.
#
# ЧАСЫ ВСЕГДА ВОЗВРАЩАЮТСЯ (trap на EXIT) — иначе эмулятор остаётся в будущем,
# и следующий прогон врёт.
#
# ТРИ ЛОВУШКИ, на которых спотыкался этот прогон (обе в духе F-63 — «проверка
# молчит, значит всё хорошо»):
#   1. Сервиса `notification_manager` в Android НЕТ (есть `notification`).
#      `dumpsys notification_manager` печатает «Can't find service», а `grep -c`
#      по нему даёт честный ноль — то есть **ложное «уведомления нет»** даже
#      тогда, когда оно на экране. Проверять показ можно только по
#      `dumpsys notification`. Скрипт проверяет, что сервис существует.
#   2. Содержимое уведомления в дампе редактируется (redaction): без
#      `--noredact` вместо заголовка видно `String [length=27]`, и «совпадает с
#      именем дня из плана» проверить нечем.
#   3. Конвейер с `grep -q` под `set -o pipefail` всегда ложен (SIGPIPE) —
#      см. scripts/emu.sh. Здесь состояния сравниваются по строкам в
#      переменных, без конвейеров.
#
# Механика срабатывания: перевод стенных часов **срывает** RTC-будильники.
# AlarmManager хранит момент в elapsed-времени, но при смене времени (как
# `date`, так и штатного `cmd alarm set-time`) пересчитывает RTC-будильники
# относительно новых часов — будильник, до которого осталось меньше проходки,
# срабатывает и показывает уведомление (F-66).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GRADLE_FILE="$REPO_ROOT/android/app/build.gradle.kts"
EMU_SERIAL="${EMU_SERIAL:-emulator-5554}"
ADB_BIN="${ADB_BIN:-adb}"
EXPECT_HHMM="${EMU_EXPECT_HHMM:-08:00}"
LEAD="${EMU_FIRE_LEAD:-60}"
TIMEOUT="${EMU_FIRE_TIMEOUT:-180}"
EXPECT_TITLE=""
DO_REPLAN=1

# Разбор аргументов индексом: значение --expect-title — произвольный текст
# (может начинаться с «-» и содержать пробелы), поэтому позиционный `shift`
# на пару не полагаемся.
args=("$@")
for i in "${!args[@]}"; do
  case "${args[$i]}" in
    --expect-title)
      NEXT=$((i + 1))
      EXPECT_TITLE="${args[$NEXT]:-}"
      [ -n "$EXPECT_TITLE" ] || { echo "emu-fire: --expect-title требует значение" >&2; exit 64; }
      ;;
    --no-replan) DO_REPLAN=0 ;;
    -*)
      [ "${args[$((i - 1))]:-}" = "--expect-title" ] && continue
      echo "emu-fire: неизвестный аргумент '${args[$i]}'" >&2; exit 64
      ;;
  esac
done
unset args NEXT

die() { echo "emu-fire: $*" >&2; exit "${EMU_FIRE_EXIT:-1}"; }

command -v "$ADB_BIN" >/dev/null 2>&1 || { echo "emu-fire: adb не найден в PATH" >&2; exit 2; }

# applicationId — из gradle, не хардкод (как в emu-perms.sh/emu-verify.sh).
if [ -z "${APP_ID:-}" ]; then
  line=""
  while IFS= read -r l; do
    case "$l" in
      *applicationId*=*) line="$l"; break ;;
    esac
  done <"$GRADLE_FILE"
  [ -n "$line" ] || { echo "emu-fire: applicationId не найден в $GRADLE_FILE" >&2; exit 2; }
  line="${line#*=}"
  line="${line#"${line%%[![:space:]]*}"}"
  line="${line%"${line##*[![:space:]]}"}"
  line="${line#\"}"
  line="${line%\"}"
  APP_ID="$line"
fi

adb_s() { "$ADB_BIN" -s "$EMU_SERIAL" "$@"; }

# Устройство подключено и загружено?
state=""
while read -r serial st _rest; do
  if [ "$serial" = "$EMU_SERIAL" ]; then state="$st"; break; fi
done <<<"$("$ADB_BIN" devices 2>/dev/null || true)"
[ "$state" = "device" ] || { echo "emu-fire: устройство $EMU_SERIAL не подключено (state='${state:-none}'); сначала scripts/emu.sh up" >&2; exit 2; }

booted="$(adb_s shell getprop sys.boot_completed 2>/dev/null | tr -d '\r\n ' || true)"
[ "$booted" = "1" ] || { echo "emu-fire: $EMU_SERIAL ещё не загружен" >&2; exit 2; }

# root нужен, чтобы менять системные часы (и только для этого).
"$ADB_BIN" -s "$EMU_SERIAL" root >/dev/null 2>&1 || true
"$ADB_BIN" -s "$EMU_SERIAL" wait-for-device >/dev/null 2>&1 || true
uid="$(adb_s shell id 2>/dev/null | tr -d '\r' || true)"
case "$uid" in
  uid=0*) : ;;
  *) echo "emu-fire: adb root недоступен (id: ${uid:-<пусто>}) — часы не перевести" >&2; exit 2 ;;
esac

# --- сервис проверки показа существует? (ловушка 1) ---
services="$(adb_s shell service list 2>/dev/null || true)"
svc_ok=0
while read -r l; do
  # Формат `service list`: «194<TAB>notification: [android.app.INotificationManager]» —
  # разделитель таб, поэтому ищем по подстроке без опоры на пробелы.
  case "$l" in
    *"notification: ["*) svc_ok=1; break ;;
  esac
done <<<"$services"
[ "$svc_ok" = "1" ] || { echo "emu-fire: сервис 'notification' не найден — проверка показа невозможна" >&2; exit 2; }

# --- часы: возврат по trap на выходе из любого места скрипта ---
restore_clock() {
  if [ "${CLOCK_JUMPED:-0}" = "1" ]; then
    # Возврат по хосту: эмулятор живёт на тех же часах, что хост.
    local stamp now_back
    stamp="$(date -d "@$(date +%s)" +%m%d%H%M%Y.%S)"
    adb_s shell "date $stamp" >/dev/null 2>&1 || true
    now_back="$(adb_s shell date 2>/dev/null | tr -d '\r' || true)"
    echo "emu-fire: часы возвращены → $now_back"
    if [ "$DO_REPLAN" = "1" ]; then
      # План после прогона частично израсходован, а сдвиг часов пересчитал
      # оставшиеся будильники: перезапуск приложения перепланирует его заново
      # (триггер «старт приложения», D-36).
      adb_s shell "am force-stop $APP_ID" >/dev/null 2>&1 || true
      adb_s shell "monkey -p $APP_ID -c android.intent.category.LAUNCHER 1" >/dev/null 2>&1 || true
    fi
  fi
}
trap restore_clock EXIT

# --- ближайший pending-будильник нашего пакета ---
alarms="$(adb_s shell dumpsys alarm 2>/dev/null || true)"
[ -n "$alarms" ] || { echo "emu-fire: пустой dumpsys alarm" >&2; EMU_FIRE_EXIT=2; die "не удалось получить данные"; }

nearest=""
nearest_epoch=""
count=0
prev1=""
prev2=""
while IFS= read -r l; do
  case "$l" in
    *"type=RTC_"*)
      ctx="$prev1$prev2"
      case "$ctx" in
        *"$APP_ID"*)
          case "$ctx" in
            *"ScheduledNotificationReceiver"*)
              count=$((count + 1))
              when=""
              case "$l" in
                *origWhen=*) rest="${l#*origWhen=}"; when="${rest%% window=*}" ;;
              esac
              if [ -n "$when" ]; then
                epoch="$(date -d "$when" +%s 2>/dev/null || true)"
                if [ -n "$epoch" ]; then
                  if [ -z "$nearest_epoch" ] || [ "$epoch" -lt "$nearest_epoch" ]; then
                    nearest_epoch="$epoch"
                    nearest="$when"
                  fi
                fi
              fi
              ;;
          esac
          ;;
      esac
      ;;
  esac
  prev2="$prev1"
  prev1="$l"
done <<<"$alarms"

echo "Пакет: $APP_ID · устройство $EMU_SERIAL · pending-записей: $count"
if [ -z "$nearest_epoch" ]; then
  # Негативный контроль: плана нет (например, уведомления выключены в
  # настройках) — срабатывания быть не может, и скрипт обязан сказать это
  # ненулевым кодом, а не «всё хорошо».
  echo "emu-fire: срабатывания нет — в плане нет pending-будильников (показ не состоится)" >&2
  exit 1
fi

nearest_local="$(date -d "@$nearest_epoch" '+%Y-%m-%d %H:%M:%S')"
echo "Ближайший pending: origWhen=$nearest (локально $nearest_local)"

# Проходка: часы встают на LEAD секунд раньше момента.
target_epoch=$((nearest_epoch - LEAD))
target_stamp="$(date -d "@$target_epoch" +%m%d%H%M%Y.%S)"
target_local="$(date -d "@$target_epoch" '+%Y-%m-%d %H:%M:%S')"

# --- отпечатки уже показанных записей нашего пакета ---
# Отпечаток = «id|posttimeElapsedMs», а не просто id:
#   1. `id=` встречается и вне строки записи (`icon=Icon(... id=0x7f0c0000)`) —
#      по такой строке «новый показ» ловился бы на иконке;
#   2. повторный показ того же id (плановое напоминание того же дня после
#      перепланирования) обязан считаться новым показом, а различить его можно
#      только по моменту публикации — uptime не убывает.
posted_fingerprints() {
  awk -v pat="pkg=$APP_ID" '
    function id_of(line) { return match(line, /id=[0-9]+/) ? substr(line, RSTART + 3, RLENGTH - 3) : "" }
    /NotificationRecord\(/ {
      if (inb) print id "|" post;
      inb = (index($0, pat) > 0);
      id = inb ? id_of($0) : ""; post = "";
      next;
    }
    inb && /posttimeElapsedMs=/ { s = $0; sub(/.*posttimeElapsedMs=/, "", s); sub(/[^0-9].*/, "", s); post = s }
    END { if (inb) print id "|" post }
  ' <<<"$1"
}

before_dump="$(adb_s shell dumpsys notification --noredact 2>/dev/null || true)"
before_fps="$(posted_fingerprints "$before_dump")"
echo "Показов до прогона: ${before_fps:-<нет>}"

# --- перевод часов ---
echo "Перевод часов: $target_local (moment - ${LEAD}s)"
adb_s shell "date $target_stamp" >/dev/null
CLOCK_JUMPED=1
sleep 2
device_now="$(adb_s shell date 2>/dev/null | tr -d '\r' || true)"
echo "Часы устройства: $device_now"
# Сверка по epoch, а не по строке: у хоста и устройства разные локали вывода
# (`Пн сен` против `Mon Sep`), и сравнение строк ложно краснело бы на живых часах.
device_epoch="$(adb_s shell date +%s 2>/dev/null | tr -d '\r\n ' || true)"
delta=$(( ${device_epoch:-0} - target_epoch ))
[ "$delta" -lt 0 ] && delta=$(( -delta ))
if [ "$delta" -gt 5 ]; then
  # Часы, которые «не перевелись», неотличимы от «будильник не сработал»:
  # проверяем перевод прежде, чем ждать показ.
  echo "emu-fire: часы не переведены — ожидался epoch $target_epoch, получен ${device_epoch:-<пусто>} (расхождение ${delta}s)" >&2
  exit 2
fi

elapsed=0
fired=0
while [ "$elapsed" -lt "$TIMEOUT" ]; do
  now="$(adb_s shell date +%H:%M:%S 2>/dev/null | tr -d '\r' || true)"
  dump="$(adb_s shell dumpsys notification --noredact 2>/dev/null || true)"
  # Новый отпечаток нашего пакета = показ состоялся.
  new_fp=""
  for fp in $(posted_fingerprints "$dump"); do
    case " $before_fps " in
      *" $fp "*) ;;
      *) new_fp="$fp" ;;
    esac
  done
  new_id="${new_fp%%|*}"
  if [ -n "$new_id" ]; then
    fired=1
    echo "--- показ состоялся на $now (id=$new_id) ---"
    # Цитата — блок ИМЕННО нашей записи: от строки `NotificationRecord(... pkg=…
    # id=…)` до следующей записи. Без этого `android.title` пришлось бы брать
    # из всего дампа, где висят чужие уведомления (ложное совпадение).
    # Конец блока — строка отступа записи (записи идут с 4 пробелов, следующий
    # раздел дампа — с двух): иначе наша запись, оказавшись последней в списке,
    # «съедает» весь остаток дампа (проверено — заголовок тогда не находится).
    block="$(printf '%s\n' "$dump" | awk -v pat="pkg=$APP_ID" -v idpat="id=$new_id " '
      !inb { if (index($0, "NotificationRecord(") > 0 && index($0, pat) > 0 && index($0, idpat) > 0) inb = 1 }
      inb && seen { if (index($0, "NotificationRecord(") > 0) exit; if ($0 ~ /^ {0,3}[^ ]/) exit; }
      inb { print; seen = 1 }')"
    # Разбор блока — регулярками bash, без конвейеров: `printf | head -1` даёт
    # SIGPIPE источнику, а `set -o pipefail` превращает это в выход 141 —
    # тот же класс ошибки, что ловушка `grep -q` в scripts/emu.sh (F-65).
    echo "${block%%$'\n'*}"
    title=""
    text=""
    when_ms=""
    # Построчно и подстановками, без regex по многострочной строке: `.` в
    # bash-регулярке матчит перевод строки, и `(.*)` жадно уходил за пределы
    # нужной строки (заголовок приходил с чужим хвостом).
    while IFS= read -r bl; do
      case "$bl" in
        *"android.title=String ("*)
          [ -n "$title" ] || { v="${bl#*android.title=String (}"; title="${v%\)}" ; } ;;
      esac
      case "$bl" in
        *"android.text=String ("*)
          [ -n "$text" ] || { v="${bl#*android.text=String (}"; text="${v%\)}" ; } ;;
      esac
      case "$bl" in
        *"when="*)
          [ -n "$when_ms" ] || { v="${bl#*when=}"; when_ms="${v%%/*}" ; } ;;
      esac
    done <<<"$block"
    echo "  when=${when_ms:-<нет>} ($(date -d "@$(( ${when_ms:-0} / 1000 ))" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo '?'))"
    echo "Заголовок: ${title:-<не найден>}"
    echo "Текст: ${text:-<не найден>}"
    if [ -n "$EXPECT_TITLE" ] && [ "$title" != "$EXPECT_TITLE" ]; then
      echo "emu-fire: заголовок не совпал с ожидаемым '$EXPECT_TITLE'" >&2
      exit 1
    fi
    break
  fi
  sleep 5
  elapsed=$((elapsed + 5))
done

if [ "$fired" != "1" ]; then
  echo "emu-fire: срабатывания нет — за ${TIMEOUT}s показ не найден (часы: ${now:-?})" >&2
  exit 1
fi

echo "OK: напоминание сработало и показано на устройстве"
