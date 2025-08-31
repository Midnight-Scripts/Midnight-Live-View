#!/usr/bin/env bash

# All-in-one block monitor with start/stop/status controls
CONTAINER_NAME="${CONTAINER_NAME:-midnight}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BLOCKS_FILE="$SCRIPT_DIR/all_blocks.json"
PID_FILE="$SCRIPT_DIR/.block_monitor.pid"
LOG_FILE="$SCRIPT_DIR/block_monitor.log"

# Colors
GREEN="\033[1;32m"; YELLOW="\033[1;33m"; CYAN="\033[1;36m"; RED="\033[1;31m"; RESET="\033[0m"

# Function to show usage
show_usage() {
    echo "Usage: $0 {start|stop|status|run}"
    echo ""
    echo "Commands:"
    echo "  start  - Start monitor in background"
    echo "  stop   - Stop background monitor"
    echo "  status - Check if monitor is running"
    echo "  run    - Run monitor in foreground (interactive)"
}

# Function to start background monitoring
start_background() {
    if [[ -f "$PID_FILE" ]]; then
        pid=$(cat "$PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            echo -e "${YELLOW}Monitor already running (PID: $pid)${RESET}"
            return 1
        fi
    fi
    
    echo -e "${GREEN}Starting block monitor in background...${RESET}"
    nohup "$0" run > "$LOG_FILE" 2>&1 &
    echo $! > "$PID_FILE"
    echo -e "${GREEN}Monitor started. Use './simple_block_monitor.sh status' to check${RESET}"
    echo -e "${GREEN}View logs: tail -f $LOG_FILE${RESET}"
}

# Function to stop background monitoring
stop_background() {
    if [[ -f "$PID_FILE" ]]; then
        pid=$(cat "$PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            echo -e "${YELLOW}Stopping monitor (PID: $pid)...${RESET}"
            kill "$pid"
            rm -f "$PID_FILE"
            echo -e "${GREEN}Monitor stopped${RESET}"
        else
            echo -e "${RED}Monitor not running (stale PID)${RESET}"
            rm -f "$PID_FILE"
        fi
    else
        echo -e "${RED}Monitor not running${RESET}"
    fi
}

# Function to check status
check_status() {
    if [[ -f "$PID_FILE" ]]; then
        pid=$(cat "$PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            echo -e "${GREEN}✅ Monitor running (PID: $pid)${RESET}"
            if [[ -f "$BLOCKS_FILE" ]]; then
                block_count=$(wc -l < "$BLOCKS_FILE")
                echo -e "${GREEN}📊 Current blocks: $block_count${RESET}"
            fi
            echo -e "${GREEN}📋 Log file: $LOG_FILE${RESET}"
        else
            echo -e "${RED}❌ Monitor not running (stale PID)${RESET}"
            rm -f "$PID_FILE"
        fi
    else
        echo -e "${RED}❌ Monitor not running${RESET}"
    fi
}

# Function to run the actual monitoring
run_monitor() {
    echo -e "${CYAN}🔍 Block Monitor Starting...${RESET}"
    echo -e "${CYAN}📁 Blocks file: $BLOCKS_FILE${RESET}"
    echo -e "${YELLOW}💡 Press Ctrl+C to stop${RESET}"
    echo ""


    # Get current count and load existing hashes
    current_count=$(wc -l < "$BLOCKS_FILE")
    echo -e "${GREEN}📊 Current blocks in file: $current_count${RESET}"
    
    echo -e "${YELLOW}🔍 Loading existing block hashes...${RESET}"
    existing_hashes=$(grep -oP '"hash": "\K0x[0-9a-fA-F]+' "$BLOCKS_FILE" | sort | uniq)
    hash_count=$(echo "$existing_hashes" | wc -l)
    echo -e "${GREEN}📋 Loaded $hash_count unique hashes${RESET}"
    echo ""

    # Simple append function
    append_new_block() {
        local datetime="$1"
        local block_num="$2"
        local hash="$3"
        local short_hash="${hash: -8}"
        local new_index=$((current_count + 1))
        
        local new_line="{\"index\": \"#$new_index\", \"datetime\": \"$datetime\", \"block\": \"$block_num\", \"hash\": \"$hash\", \"short_hash\": \"$short_hash\"}"
        echo "$new_line" >> "$BLOCKS_FILE"
        
        echo -e "${GREEN}✅ NEW Block #$block_num added (Total: $new_index)${RESET}"
        ((current_count++))
    }

    # Cleanup function
    cleanup() {
        echo -e "\n${YELLOW}🛑 Stopping monitor...${RESET}"
        rm -f "$PID_FILE"
        exit 0
    }

    trap cleanup SIGINT SIGTERM

    echo -e "${CYAN}👀 Watching for NEW blocks only...${RESET}"

    # Monitor with timestamp to only get new logs
    docker logs --follow --since "$(date -u +"%Y-%m-%dT%H:%M:%S")" "$CONTAINER_NAME" 2>&1 | grep --line-buffered "Pre-sealed block" | while IFS= read -r line; do
        # Parse the line
        datetime=$(echo "$line" | awk '{print $1, $2}')
        block_num=$(echo "$line" | grep -oP 'proposal at \K[0-9]+')
        hash=$(echo "$line" | grep -oP 'Hash now \K0x[0-9a-fA-F]+')
        
        if [[ -n "$hash" && -n "$block_num" ]]; then
            # Check if this hash already exists in our file
            if ! echo "$existing_hashes" | grep -q "^$hash$"; then
                echo -e "${YELLOW}🆕 TRULY NEW block: #$block_num | $datetime | ${hash:0:18}...${RESET}"
                append_new_block "$datetime" "$block_num" "$hash"
                # Add to our existing hashes list
                existing_hashes="$existing_hashes"$'\n'"$hash"
            else
                echo -e "${RED}⚠️  Duplicate block ignored: #$block_num | ${hash:0:18}...${RESET}"
            fi
        fi
    done
}

# Main script logic
case "$1" in
    start)
        start_background
        ;;
    stop)
        stop_background
        ;;
    status)
        check_status
        ;;
    run)
        run_monitor
        ;;
    *)
        show_usage
        exit 1
        ;;
esac
