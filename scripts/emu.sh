#!/usr/bin/env bash
# Жизненный цикл headless-эмулятора Android для пакета 6.3 (android-emu-0/B).
#
# Зачем: агенту нужен воспроизводимый CLI-доступ к эмулятору — без GUI-действий
# и без риска поднять второй инстанс того же AVD.
#
# Использование:
#   scripts/emu.sh up         # поднять AVD (идемпотентно) и дождаться загрузки
#   scripts/emu.sh down       # погасить (adb emu kill) и дождаться исчезновения
#   scripts/emu.sh status     # BOOT_OK | BOOTING | none
#   scripts/emu.sh wait-boot  # дождаться готовности уже запущенного
#
# Переменные окружения (все опциональны):
#   AVD_NAME         — имя AVD (default: dharma35)
#   EMU_SERIAL       — серийник эмулятора (default: emulator-5554)
#   EMU_BOOT_TIMEOUT — секунд на загрузку (default: 600; холодный старт AVD
#                      на headless-хосте — ~205s boot + дозревание system_server)
#   EMU_GPU          — режим GPU (default: swiftshader_indirect — headless-надёжно)
#
# Exit-коды status: 0 = BOOT_OK, 1 = BOOTING, 2 = none.
#
# ВАЖНО (ловушка, найденная при отладке этого скрипта): проверки состояния
# намеренно НЕ используют конвейер вида `flutter devices | grep -q ...`.
# `grep -q` завершается на первом совпадении, источник получает SIGPIPE (141),
# а `set -o pipefail` превращает это в ненулевой статус конвейера — условие
# становится ложным именно тогда, когда устройство найдено. Сравнения идут
# по строке, полученной в переменную, без пайпов.

set -euo pipefail

AVD_NAME="${AVD_NAME:-dharma35}"
EMU_SERIAL="${EMU_SERIAL:-emulator-5554}"
EMU_BOOT_TIMEOUT="${EMU_BOOT_TIMEOUT:-600}"
EMU_GPU="${EMU_GPU:-swiftshader_indirect}"
EMU_LOG="${EMU_LOG:-/tmp/emu-${AVD_NAME}.log}"

ADB_BIN="${ADB_BIN:-adb}"
ANDROID_HOME_DIR="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/software/android_sdk}}"
EMULATOR_BIN="${EMULATOR_BIN:-$ANDROID_HOME_DIR/emulator/emulator}"

die() { echo "emu: $*" >&2; exit 1; }

require_tools() {
  command -v "$ADB_BIN" >/dev/null 2>&1 || die "adb не найден в PATH"
  [ -x "$EMULATOR_BIN" ] || die "эмулятор не найден: $EMULATOR_BIN (ANDROID_HOME=$ANDROID_HOME_DIR)"
}

# Обрезает пробелы/CR/LF по краям (без внешних процессов).
trim() {
  local s="$1"
  s="${s//$'\r'/}"
  s="${s//$'\n'/}"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

# Состояние устройства по `adb devices`: device | offline | unauthorized | "" (нет).
serial_state() {
  local out serial state
  out="$("$ADB_BIN" devices 2>/dev/null || true)"
  while read -r serial state _rest; do
    if [ "$serial" = "$EMU_SERIAL" ]; then
      printf '%s' "$state"
      return 0
    fi
  done <<<"$out"
  printf ''
}

# Серийник запущенного эмулятора, чей AVD называется AVD_NAME ("" если нет).
avd_serial() {
  local out serial state name
  out="$("$ADB_BIN" devices 2>/dev/null || true)"
  while read -r serial state _rest; do
    case "$serial" in
      emulator-[0-9]*)
        [ "$state" = "device" ] || continue
        name="$("$ADB_BIN" -s "$serial" emu avd name 2>/dev/null || true)"
        name="${name%%$'\n'*}"
        name="$(trim "$name")"
        if [ "$name" = "$AVD_NAME" ]; then
          printf '%s' "$serial"
          return 0
        fi
        ;;
    esac
  done <<<"$out"
  printf ''
}

is_booted() {
  local v
  v="$("$ADB_BIN" -s "$EMU_SERIAL" shell getprop sys.boot_completed 2>/dev/null || true)"
  [ "$(trim "$v")" = "1" ]
}

# Видим ли серийник в flutter devices (сравнение по строке, без пайпов).
wait_flutter_devices() {
  local out
  command -v flutter >/dev/null 2>&1 || return 0
  out="$(flutter devices 2>/dev/null || true)"
  case "$out" in
    *"$EMU_SERIAL"*) return 0 ;;
    *) return 1 ;;
  esac
}

cmd_status() {
  require_tools
  case "$(serial_state)" in
    '') echo "none"; return 2 ;;
    device)
      if is_booted; then echo "BOOT_OK"; return 0; fi
      echo "BOOTING"; return 1
      ;;
    *) echo "offline"; return 1 ;;
  esac
}

cmd_wait_boot() {
  require_tools
  local waited=0 after_boot=0 booted_at=""
  while [ "$waited" -lt "$EMU_BOOT_TIMEOUT" ]; do
    if is_booted; then
      booted_at="${booted_at:-$waited}"
      # sys.boot_completed=1 — это ещё не готовность для flutter: system_server
      # дозревает (на холодном старте ~30–90s), и flutter devices устройства
      # какое-то время не видит. Контракт wait-boot — оба условия.
      if wait_flutter_devices; then
        echo "BOOT_OK ($EMU_SERIAL виден в flutter devices; boot ${booted_at}s, всего ${waited}s)"
        return 0
      fi
      after_boot=$((after_boot + 5))
      if [ $((after_boot % 30)) -eq 0 ]; then
        echo "emu: sys.boot_completed=1, $EMU_SERIAL ещё не виден в flutter devices (${after_boot}s после boot)" >&2
      fi
    fi
    sleep 5
    waited=$((waited + 5))
  done
  die "загрузка не завершилась за ${EMU_BOOT_TIMEOUT}s (лог: $EMU_LOG)"
}

cmd_up() {
  require_tools
  "$ADB_BIN" start-server >/dev/null 2>&1 || true

  local existing
  existing="$(avd_serial)"
  if [ -n "$existing" ]; then
    echo "emu: AVD '$AVD_NAME' уже запущен ($existing) — второй инстанс не поднимаю"
    EMU_SERIAL="$existing" cmd_wait_boot
    return 0
  fi

  if [ "$(serial_state)" = "device" ]; then
    echo "emu: $EMU_SERIAL уже подключён (AVD не определён) — переиспользую"
    cmd_wait_boot
    return 0
  fi

  echo "emu: старт $AVD_NAME (headless, gpu=$EMU_GPU), лог: $EMU_LOG"
  nohup "$EMULATOR_BIN" -avd "$AVD_NAME" \
    -no-window -no-audio -no-boot-anim \
    -no-snapshot-save -gpu "$EMU_GPU" \
    >"$EMU_LOG" 2>&1 &

  local waited=0
  while [ "$waited" -lt 120 ]; do
    [ "$(serial_state)" != "" ] && break
    sleep 2
    waited=$((waited + 2))
  done
  [ "$(serial_state)" != "" ] || die "эмулятор не появился в adb devices за 120s (лог: $EMU_LOG)"
  cmd_wait_boot
}

cmd_down() {
  require_tools
  if [ "$(serial_state)" = "" ]; then
    echo "emu: эмулятор не запущен"
    return 0
  fi
  "$ADB_BIN" -s "$EMU_SERIAL" emu kill >/dev/null 2>&1 || true
  local waited=0
  while [ "$waited" -lt 60 ]; do
    [ "$(serial_state)" = "" ] && break
    sleep 2
    waited=$((waited + 2))
  done
  [ "$(serial_state)" = "" ] || die "эмулятор не погас за 60s"
  echo "emu: погашен"
}

case "${1:-}" in
  up) cmd_up ;;
  down) cmd_down ;;
  status) cmd_status ;;
  wait-boot) cmd_wait_boot ;;
  *)
    echo "Использование: $0 up|down|status|wait-boot" >&2
    exit 64
    ;;
esac
