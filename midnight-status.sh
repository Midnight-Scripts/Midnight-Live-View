#!/usr/bin/env bash

# ================== 設定 ==================
BLOCKS_CMD_REGEX="simple_block_monitor.sh run"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BLOCKS_PID_FILE="$SCRIPT_DIR/.block_monitor.pid"

SERVICES=(
  "cardano-node|systemd|cardano-node|cardano-node"
  "cardano-db-sync|systemd|cardano-db-sync|cardano-db-sync"
  "midnight-node|systemd|midnight-node|midnight-node"
  "midnight-blocks|exec|$BLOCKS_CMD_REGEX|midnight-blocks"
)

# ================== 色 ==================
RED="\033[31m"; GREEN="\033[32m"; YELLOW="\033[33m"
BLUE="\033[34m"; GRAY="\033[90m"; RESET="\033[0m"

color_status_field() {
  # $1: raw status, $2: padded display text
  case "$1" in
    active)   printf "${GREEN}%s${RESET}" "$2" ;;
    inactive) printf "${YELLOW}%s${RESET}" "$2" ;;
    failed)   printf "${RED}%s${RESET}" "$2" ;;
    STOPPED)  printf "${GRAY}%s${RESET}" "$2" ;;
    *)        printf "${GRAY}%s${RESET}" "$2" ;;
  esac
}

cleanup_terminal() {
  tput cnorm 2>/dev/null || true
}

init_terminal() {
  tput civis 2>/dev/null || true
  trap cleanup_terminal EXIT INT TERM
}

# ================== midnight-blocks PID検出（最重要） ==================
# 「コマンド行の末尾が 'simple_block_monitor.sh run'」のものだけを採用。
# PIDファイルが存在していて生きていればそれを優先し、なければ一番新しく起動したものを使う。
get_blocks_pid() {
  if [[ -f "$BLOCKS_PID_FILE" ]]; then
    local pid
    pid=$(cat "$BLOCKS_PID_FILE")
    if [[ "$pid" =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null; then
      echo "$pid"
      return
    fi
  fi

  local newest_pid=""
  local newest_ticks=0

  while IFS= read -r pid; do
    [[ "$pid" =~ ^[0-9]+$ ]] || continue
    kill -0 "$pid" 2>/dev/null || continue

    local start_ticks
    start_ticks=$(awk '{print $22}' "/proc/$pid/stat" 2>/dev/null) || continue

    if (( start_ticks > newest_ticks )); then
      newest_ticks=$start_ticks
      newest_pid=$pid
    fi
  done < <(
    pgrep -af "$BLOCKS_CMD_REGEX" \
      | awk '$0 ~ /simple_block_monitor\.sh run$/ {print $1}'
  )

  [[ -n "$newest_pid" ]] && echo "$newest_pid"
}

# ================== midnight-blocks 情報取得 ==================
get_blocks_info() {
  local pid
  pid=$(get_blocks_pid)

  [[ -n "$pid" ]] || { echo "STOPPED|-|-|-|-"; return; }

  # CPU
  local cpu
  cpu=$(ps -p "$pid" -o %cpu= | awk '{printf "%.1f",$1}')

  # RSS (GB)
  local rss_kb rss
  rss_kb=$(ps -p "$pid" -o rss=)
  rss=$(awk "BEGIN {printf \"%.2f\", $rss_kb/1024/1024}")

  # STARTED AT / epoch（/proc）
  local btime start_ticks hz start_epoch started_at
  btime=$(awk '/btime/{print $2}' /proc/stat)
  start_ticks=$(awk '{print $22}' "/proc/$pid/stat")
  hz=$(getconf CLK_TCK)
  start_epoch=$(( btime + start_ticks / hz ))
  started_at=$(date -u -d "@$start_epoch" "+%a %Y-%m-%d %H:%M:%S UTC")

  echo "active|$cpu|$rss|$started_at|$start_epoch"
}

# ================== カラム（メンテしやすく） ==================
# ここだけ触れば列幅を調整できる
COL_GAP=1
W_SERVICE=18
W_STATUS=10
W_CPU=8
W_RSS=10
W_START=32
W_UPTIME=12
VALUE_OFFSET=1

# 0-basedの開始位置は幅から自動計算
COL_SERVICE=0
COL_STATUS=$((COL_SERVICE + W_SERVICE + COL_GAP))
COL_CPU=$((COL_STATUS + W_STATUS + COL_GAP))
COL_RSS=$((COL_CPU + W_CPU + COL_GAP))
COL_START=$((COL_RSS + W_RSS + COL_GAP))
COL_UPTIME=$((COL_START + W_START + COL_GAP))

FMT="%-${W_SERVICE}s %-${W_STATUS}s %-${W_CPU}s %-${W_RSS}s %-${W_START}s %-${W_UPTIME}s\n"

repeat_char() {
  local n="$1"
  local ch="${2:--}"
  printf '%*s' "$n" '' | tr ' ' "$ch"
}

DATA_COL_SERVICE=$((COL_SERVICE + VALUE_OFFSET))
DATA_COL_STATUS=$((COL_STATUS + VALUE_OFFSET + 1))
DATA_COL_CPU=$((COL_CPU + VALUE_OFFSET + 1))
DATA_COL_RSS=$((COL_RSS + VALUE_OFFSET + 1))
DATA_COL_START=$((COL_START + VALUE_OFFSET + 1))
DATA_COL_UPTIME=$((COL_UPTIME + VALUE_OFFSET + 1))

clear
init_terminal
printf "$FMT" \
  "SERVICE" "STATUS" "CPU%" "RSS(GB)" "STARTED AT (UTC)" "UPTIME"
printf "$FMT" \
  "$(repeat_char "$W_SERVICE")" \
  "$(repeat_char "$W_STATUS")" \
  "$(repeat_char "$W_CPU")" \
  "$(repeat_char "$W_RSS")" \
  "$(repeat_char "$W_START")" \
  "$(repeat_char "$W_UPTIME")"

# サービス名固定描画
for i in "${!SERVICES[@]}"; do
  IFS='|' read -r name _ _ _ <<<"${SERVICES[$i]}"
  tput cup $((i + 2)) "$DATA_COL_SERVICE"
  printf "%-*s" "$W_SERVICE" "$name"
done

while true; do
  # systemd用（monotonic）
  system_uptime=$(awk '{print int($1)}' /proc/uptime)
  # exec用（epoch）
  now_epoch=$(date +%s)

  BUFFER=""

  for i in "${!SERVICES[@]}"; do
    IFS='|' read -r name type ref proc <<<"${SERVICES[$i]}"
    row=$((i + 2))

    raw_status="-"
    cpu="-"
    rss="-"
    started_at="-"
    uptime="-"

    if [[ "$type" == "systemd" ]]; then
      if systemctl list-unit-files | grep -q "^${ref}.service"; then
        raw_status=$(systemctl is-active "$ref")
        started_at=$(systemctl show "$ref" -p ActiveEnterTimestamp --value)
        started_mono=$(systemctl show "$ref" -p ActiveEnterTimestampMonotonic --value)

        if [[ "$raw_status" == "active" ]]; then
          cpu=$(ps -C "$proc" -o %cpu= --sort=-%cpu | head -n1 | awk '{printf "%.1f",$1}')
          rss_kb=$(ps -C "$proc" -o rss= --sort=-rss | head -n1)
          rss=$(awk "BEGIN {printf \"%.2f\", $rss_kb/1024/1024}")

          # UPTIME（monotonic同士）
          start_sec=$(( started_mono / 1000000 ))
          up=$(( system_uptime - start_sec ))
          printf -v uptime "%dd %dh %dm %ds" \
            $((up/86400)) $(((up%86400)/3600)) $(((up%3600)/60)) $((up%60))
        fi
      fi

    else
      IFS='|' read -r raw_status cpu rss started_at start_epoch \
        <<<"$(get_blocks_info)"

      if [[ "$raw_status" == "active" ]]; then
        # UPTIME（epoch同士）
        up=$(( now_epoch - start_epoch ))
        printf -v uptime "%dd %dh %dm %ds" \
          $((up/86400)) $(((up%86400)/3600)) $(((up%3600)/60)) $((up%60))
      fi
    fi

    started_at_fixed=$(printf "%.${W_START}s" "$started_at")
    status_text=$(printf "%-*s" "$W_STATUS" "$raw_status")
    status=$(color_status_field "$raw_status" "$status_text")

    BUFFER+=$(printf "\033[%d;%dH%b"        "$((row+1))" "$DATA_COL_STATUS" "$status")
    BUFFER+=$(printf "\033[%d;%dH%-*s"       "$((row+1))" "$DATA_COL_CPU"    "$W_CPU" "$cpu")
    BUFFER+=$(printf "\033[%d;%dH%-*s"       "$((row+1))" "$DATA_COL_RSS"    "$W_RSS" "$rss")
    BUFFER+=$(printf "\033[%d;%dH%-*s"      "$((row+1))" "$DATA_COL_START"  "$W_START" "$started_at_fixed")
    BUFFER+=$(printf "\033[%d;%dH%-*s"      "$((row+1))" "$DATA_COL_UPTIME" "$W_UPTIME" "$uptime")
  done

  tput sc
  printf "%b" "$BUFFER"
  tput rc

  sleep 5
done
