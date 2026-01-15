#!/usr/bin/env bash

# ─── USER VARIABLES ────────────────────────────────
CONTAINER_NAME="${CONTAINER_NAME:-midnight}"
PORT="${PORT:-9944}"
USE_DOCKER="${USE_DOCKER:-true}"

# ─── PATHS ─────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$HOME/midnight-node-docker/.envrc"
KEYS_FILE="$SCRIPT_DIR/partner-chains-public-keys.json"
RPC_URL="http://127.0.0.1:$PORT"

# ─── COLORS ───────────────────────────────────────
GREEN="\033[1;32m"; RED="\033[1;31m"; YELLOW="\033[1;33m"
CYAN="\033[1;36m"; WHITE="\033[1;37m"; BLUE="\033[1;34m"; RESET="\033[0m"

declare -A KEY_ITEMS=( ["grandpa_pub_key"]="gran" ["aura_pub_key"]="aura" ["sidechain_pub_key"]="crch" )
declare -A KEY_RESULTS
declare -A PUBLIC_KEYS

# Check for required dependencies
check_dependencies(){
  if [[ "$USE_DOCKER" == true ]]; then
    required_deps=(jq curl top free df awk date uptime grep cut tr docker)
  else
    required_deps=(jq curl top free df awk date uptime grep cut tr)
  fi
  for cmd in "${required_deps[@]}"; do
    if ! command -v "$cmd" &> /dev/null; then
      echo "Required dependency not found: $cmd"
      exit 1
    fi
  done
}

execute_command(){
  if [[ "$USE_DOCKER" == true ]]; then
    docker exec "$CONTAINER_NAME" "$@"
  else
    "$@"
  fi
}

# Retry wrapper for curl with up to 3 attempts
retry_curl() {
  local attempt=0
  local max_attempts=3
  local response

  while (( attempt < max_attempts )); do
    response=$(curl -s "$@")
    if [[ -n "$response" && "$response" != "null" ]]; then
      echo "$response"
      return 0
    fi
    ((attempt++))
    sleep 1
  done

  echo ""
  return 1
}

fetch_static_data(){
  NODE_KEY=$(grep -E '^NODE_KEY=' "$ENV_FILE" | cut -d= -f2 | tr -d '"')
  for key in "${!KEY_ITEMS[@]}"; do
    PUBLIC_KEYS[$key]=$(jq -r ".${key}" "$KEYS_FILE")
  done
}

fetch_dynamic_data(){
  UPTIME=$(uptime -p)
  CONTAINER_START=$(docker inspect -f '{{.State.StartedAt}}' "$CONTAINER_NAME" 2>/dev/null | cut -d'.' -f1)
  START_FMT=$(date -d "$CONTAINER_START" +"%Y-%m-%d %H:%M:%S" 2>/dev/null)

  CPU=$(top -bn1 | grep "Cpu(s)" | awk '{print $2+$4}')
  MEM=$(free -m | awk 'NR==2{printf "%.2f GiB",$3/1024}')
  DISK=$(df -h / | awk 'NR==2{print $5}')

  # Peers fetch with error handling
  PEERS_JSON=$(execute_command curl -s -X POST \
    -d '{"jsonrpc":"2.0","id":1,"method":"system_peers","params":[]}' \
    -H "Content-Type:application/json" "$RPC_URL")
  if [[ -z "$PEERS_JSON" || "$PEERS_JSON" == "null" ]]; then
    echo -e "${RED}Failed to fetch peers data${RESET}"
    PEERS=0
  else
    PEERS=$(echo "$PEERS_JSON" | jq '.result|length')
  fi

  # Latest block with retry and error check
  LATEST_JSON=$(retry_curl -X POST \
    -d '{"jsonrpc":"2.0","id":1,"method":"chain_getHeader","params":[]}' \
    -H "Content-Type:application/json" "$RPC_URL")
  if [[ -z "$LATEST_JSON" || "$LATEST_JSON" == "null" ]]; then
    echo -e "${RED}Failed to fetch latest block${RESET}"
    NETWORK_LATEST_BLOCK=0
  else
    LATEST_HEX=$(echo "$LATEST_JSON" | jq -r '.result.number')
    NETWORK_LATEST_BLOCK=$((LATEST_HEX))
  fi

  # Finalized hash and block with retry/error check
  FINALIZED_HASH=$(retry_curl -X POST \
    -d '{"jsonrpc":"2.0","id":1,"method":"chain_getFinalizedHead","params":[]}' \
    -H "Content-Type:application/json" "$RPC_URL" | jq -r '.result')
  if [[ -z "$FINALIZED_HASH" || "$FINALIZED_HASH" == "null" ]]; then
    echo -e "${RED}Failed to fetch finalized hash${RESET}"
    FINALIZED_BLOCK=0
  else
    FINALIZED_HEADER_JSON=$(retry_curl -X POST \
      -d "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"chain_getHeader\",\"params\":[\"$FINALIZED_HASH\"]}" \
      -H "Content-Type:application/json" "$RPC_URL")
    if [[ -z "$FINALIZED_HEADER_JSON" || "$FINALIZED_HEADER_JSON" == "null" ]]; then
      echo -e "${RED}Failed to fetch finalized block header${RESET}"
      FINALIZED_BLOCK=0
    else
      FINALIZED_HEX=$(echo "$FINALIZED_HEADER_JSON" | jq -r '.result.number')
      FINALIZED_BLOCK=$((FINALIZED_HEX))
    fi
  fi

  # Sync target with retry/error check
  SYNC_JSON=$(retry_curl -X POST \
    -d '{"jsonrpc":"2.0","id":1,"method":"system_syncState","params":[]}' \
    -H "Content-Type:application/json" "$RPC_URL")
  if [[ -z "$SYNC_JSON" || "$SYNC_JSON" == "null" ]]; then
    echo -e "${RED}Failed to fetch sync state${RESET}"
    SYNC_TARGET=0
    SYNC_PERCENTAGE="N/A"
  else
    SYNC_TARGET=$(echo "$SYNC_JSON" | jq -r '.result.highestBlock')
    if [[ $SYNC_TARGET -gt 0 && $NETWORK_LATEST_BLOCK -gt 0 ]]; then
      SYNC_PERCENTAGE=$(awk "BEGIN{printf \"%.2f\",($NETWORK_LATEST_BLOCK/$SYNC_TARGET)*100}")
    else
      SYNC_PERCENTAGE="N/A"
    fi
  fi

  # Blocks produced (metrics endpoint, with error check)
  METRICS=$(retry_curl http://127.0.0.1:9615/metrics)
  if [[ -z "$METRICS" ]]; then
    BLOCKS_PRODUCED="N/A"
  else
    BLOCKS_PRODUCED=$(echo "$METRICS" | awk -F' ' '/substrate_tasks_ended_total{.*basic-authorship-proposer/ {print $2}')
    [[ -z "$BLOCKS_PRODUCED" ]] && BLOCKS_PRODUCED="N/A"
  fi

  # Node version with retry/error check
  NODE_VERSION_JSON=$(retry_curl -X POST \
    -d '{"jsonrpc":"2.0","id":1,"method":"system_version","params":[]}' \
    -H "Content-Type:application/json" "$RPC_URL")
  if [[ -z "$NODE_VERSION_JSON" || "$NODE_VERSION_JSON" == "null" ]]; then
    NODE_VERSION="N/A"
  else
    NODE_VERSION=$(echo "$NODE_VERSION_JSON" | jq -r '.result')
  fi

  # Fetch sidechain/mainchain epoch info with retry/error check
  EPOCH_JSON=$(retry_curl -X POST -H "Content-Type: application/json" \
    -d '{"jsonrpc":"2.0","method":"sidechain_getStatus","params":[],"id":1}' \
    https://rpc.testnet-02.midnight.network)
  if [[ -z "$EPOCH_JSON" || "$EPOCH_JSON" == "null" ]]; then
    echo -e "${RED}Failed to fetch epoch data${RESET}"
    MAINCHAIN_EPOCH="N/A"
    SIDECHAIN_REG_STATUS="❓ Unknown"
  else
    MAINCHAIN_EPOCH=$(echo "$EPOCH_JSON" | jq -r '.result.mainchain.epoch')
    # Check sidechain registration status with retry/error check
    local target_key="${PUBLIC_KEYS[sidechain_pub_key]}"
    local result=$(retry_curl -X POST -H "Content-Type: application/json" \
      -d "{\"jsonrpc\":\"2.0\",\"method\":\"sidechain_getAriadneParameters\",\"params\":[${MAINCHAIN_EPOCH}],\"id\":1}" \
      https://rpc.testnet-02.midnight.network)
    if [[ -z "$result" || "$result" == "null" ]]; then
      echo -e "${RED}Failed to fetch sidechain registration status${RESET}"
      SIDECHAIN_REG_STATUS="❓ Unknown"
    elif echo "$result" | grep -q "$target_key"; then
      SIDECHAIN_REG_STATUS="✅ Registered"
    else
      SIDECHAIN_REG_STATUS="❌ Not Registered"
    fi
  fi
  # Fetch node libp2p peer ID as node key
  NODE_KEY_JSON=$(retry_curl -X POST \
    -d '{"jsonrpc":"2.0","id":1,"method":"system_localPeerId","params":[]}' \
    -H "Content-Type: application/json" "$RPC_URL")
  if [[ -z "$NODE_KEY_JSON" || "$NODE_KEY_JSON" == "null" ]]; then
    NODE_KEY="Unavailable"
  else
    NODE_KEY=$(echo "$NODE_KEY_JSON" | jq -r '.result')
  fi
}

check_keys(){
  for name in "${!KEY_ITEMS[@]}"; do
    pub=${PUBLIC_KEYS[$name]}
    KEY_RESULTS[$name]=$(execute_command curl -s \
      -d '{"jsonrpc":"2.0","id":1,"method":"author_hasKey","params":["'"$pub"'","'"${KEY_ITEMS[$name]}"'"]}' \
      -H "Content-Type:application/json" "$RPC_URL" | jq -r '.result')
  done
}

display_dashboard(){
  tput reset
  tput cup 0 0
  echo -e "\n  |     ${CYAN}🔵 Midnight Node Monitor - Version: ${WHITE}$NODE_VERSION${RESET}"
  echo -e "  |  LiveView version 0.2.1"
  echo "  |================================================================"
  echo -e "  | ⏳ Uptime:           ${YELLOW}$UPTIME${RESET}"
  echo -e "  | 🚀 Start Time:       ${GREEN}$START_FMT${RESET}"
  echo "  |----------------------------------------------------------------"
  # Abbreviate node key for display, handle unavailable
  if [[ "$NODE_KEY" == "Unavailable" ]]; then
    echo -e "  | 🔑 Node Key: ${RED}Unavailable${RESET}"
  else
    ABBR_NODE_KEY="${NODE_KEY:0:13}......${NODE_KEY: -11}"
    echo -e "  | 🔑 Node Key: ${WHITE}$ABBR_NODE_KEY${RESET}"
  fi
  echo -e "  | 📡 RPC Port:         ${WHITE}$PORT${RESET}"
  echo "  |----------------------------------------------------------------"
  echo -e "  | 🔐 Keys:"
  for key in "${!KEY_ITEMS[@]}"; do
      status=${KEY_RESULTS[$key]}
      pub=${PUBLIC_KEYS[$key]}
      short_key="${pub:0:18}..."
      if [[ "$status" == "true" ]]; then
          if [[ "$key" == "sidechain_pub_key" ]]; then
              printf "  |    %-18s: %b✓ %s (%s)%b\n" "$key" "$GREEN" "$short_key" "$SIDECHAIN_REG_STATUS" "$RESET"
          else
              printf "  |    %-18s: %b✓ %s%b\n" "$key" "$GREEN" "$short_key" "$RESET"
          fi
      else
          printf "  |    %-18s: %b✗ Key not found%b\n" "$key" "$RED" "$RESET"
      fi
  done
  echo "  |----------------------------------------------------------------"
  echo -e "  | 📚 Historic Blocks:  ${WHITE}$HISTORIC_BLOCKS${RESET} Since monitoring started"
  echo -e "  | 📦 Blocks Produced:  ${WHITE}$BLOCKS_PRODUCED${RESET} Since Docker restart"
  echo -e "  | 🧭 Epoch:            ${WHITE}$MAINCHAIN_EPOCH${RESET}"
  echo "  |----------------------------------------------------------------"
  echo -e "  | 🌍 Latest Block:     ${GREEN}$NETWORK_LATEST_BLOCK${RESET}"
  echo -e "  | ✅ Finalized Block:  ${GREEN}$FINALIZED_BLOCK${RESET}"
  echo -e "  | 📊 Sync:             ${CYAN}$SYNC_PERCENTAGE%${RESET}"
  echo -e "  | 👥 Peers:            ${YELLOW}$PEERS${RESET}"
  echo "  |----------------------------------------------------------------"
  echo -e "  | 🔥 CPU:              ${RED}$CPU%${RESET}"
  echo -e "  | 💾 MEM:              ${BLUE}$MEM${RESET}"
  echo -e "  | 💽 Disk:             ${CYAN}$DISK${RESET}"
  echo "  |================================================================"
  echo "  | [q] Quit | [p] Peers"
}

show_peers(){
  tput reset
  echo -e "\n  |  🔍 Connected Peers:"
  echo "  |  --------------------------------------------------------------"
  PEERS_JSON=$(execute_command curl -s -X POST \
    -d '{"jsonrpc":"2.0","id":1,"method":"system_peers","params":[]}' \
    -H "Content-Type:application/json" "$RPC_URL")
  if [[ -z "$PEERS_JSON" || "$PEERS_JSON" == "null" ]]; then
    echo "  |  ❌ No peers connected."
  else
    echo "$PEERS_JSON" | jq -r '.result[] | "  |  🔹 Peer ID: " + .peerId + " | Role: " + .roles + " | Best Block: " + (.bestNumber|tostring)'
  fi
  echo "  |  --------------------------------------------------------------"
  echo "  |  [r] Return | [q] Quit"
  # tput reset
  while true; do
    read -rsn1 input
    case "$input" in
      r) return ;;
      q) clear && exit ;;
    esac
  done
}

tput civis  # Hide cursor
trap "tput cnorm; clear; exit" SIGINT SIGTERM

check_dependencies
fetch_static_data
check_keys


# Count historic blocks from all_blocks.json
get_historic_blocks_count() {
  ALL_BLOCKS_FILE="$SCRIPT_DIR/all_blocks.json"
  if [[ -f "$ALL_BLOCKS_FILE" ]]; then
    HISTORIC_BLOCKS=$(wc -l < "$ALL_BLOCKS_FILE" 2>/dev/null || echo "0")
  else
    HISTORIC_BLOCKS="0"
  fi
}

while true; do
  fetch_dynamic_data
  get_historic_blocks_count
  display_dashboard
  read -rsn1 -t 1 key
  case "$key" in
    q) tput cnorm; clear; exit ;;
    p) show_peers ;;
  esac
done
