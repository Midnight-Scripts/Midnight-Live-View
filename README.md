# Midnight Node Monitoring
## Inspired by CNTool's gLiveView
### Thanks to @RcadaPool SPO for his key‑checker script.

LiveView version 0.2.1
Tested on Midnight Validator Node - Testnet - Version: 0.12.0-cab67f3b



A comprehensive monitoring solution for Midnight blockchain nodes, featuring real-time dashboard monitoring and persistent block tracking.

<img width="517" height="423" alt="Screenshot 2025-08-18 at 11 47 56 AM" src="https://github.com/user-attachments/assets/46641438-de25-457f-9dc5-90e57e761910" />

## What's Included

- **LiveView.sh** - Real-time monitoring dashboard (inspired by CNTool's gLiveView)
- **simple_block_monitor.sh** - Persistent block tracking that survives Docker restarts
- **Integration** - Historic block counting that shows total blocks since monitoring started

---
## Tested
Midnight Node Monitor - Version: 0.12.0-29935d2f

## Prerequisites

### Required Dependencies
- `jq` - Command-line JSON processor
- `curl` - For API calls
- `docker` - If using Docker deployment
- Standard utilities: `awk`, `date`, `grep`, etc.

### Required Files
1. `partner-chains-public-keys.json` - Must be in the same directory as LiveView.sh
2. Midnight node running (Docker container named "midnight" by default)

### Node Configuration
To enable full monitoring features, update your `.envrc` file:

**Modify the `APPEND_ARGS` line:**

If you have 2 server setup ( Side chain on one and Midnight node on one )
```bash
# From:
export APPEND_ARGS="--allow-private-ip --pool-limit 10 --trie-cache-size 0 --prometheus-external --rpc-external"

# To:
export APPEND_ARGS="--validator --allow-private-ip --pool-limit 10 --trie-cache-size 0 --prometheus-external --unsafe-rpc-external --rpc-methods=Unsafe --rpc-cors all"
```
If you have 1 server setup ( Side chain and Midnight node on same server )
```bash
# From:
export APPEND_ARGS="--allow-private-ip --pool-limit 10 --trie-cache-size 0 --prometheus-external --rpc-external"

# To:
export APPEND_ARGS="--validator --allow-private-ip --pool-limit 10 --trie-cache-size 0 --prometheus-external --unsafe-rpc-external --rpc-methods=Unsafe --rpc-cors all --rpc-port 9944 --keystore-path=/data/chains/partner_chains_template/keystore/"
```
NOTE = Change the key store path if necessary

---

## Installation & Setup

### 1. Download the Files
```bash
# Download all files to your preferred directory
wget -O ./LiveView.sh  https://raw.githubusercontent.com/Midnight-Scripts/Midnight-Live-View/refs/heads/main/LiveView.sh
wget -O ./simple_block_monitor.sh  https://raw.githubusercontent.com/Midnight-Scripts/Midnight-Live-View/refs/heads/main/simple_block_monitor.sh
chmod +x LiveView.sh simple_block_monitor.sh
```

### 2. Basic Setup (LiveView Only)
```bash
# Just run the dashboard
./LiveView.sh
```

### 3. Full Setup (Dashboard + Persistent Tracking)
```bash
# Step 1: Start the block monitor (creates all_blocks.json)
./simple_block_monitor.sh start

# Step 2: Run the dashboard (will show historic blocks)
./LiveView.sh
```

---

## LiveView.sh - Real-Time Dashboard

### Features
- **Node Information**: Version, uptime, container start time
- **Security**: Node key (masked), port, key status
- **Registration**: Registration status
- **Block Data**: 
  - Historic blocks (total since monitoring started)
  - Blocks produced (since Docker restart)
  - Latest/finalized blocks, sync status
- **Network**: Peer count and details
- **System**: CPU, memory, disk usage

### Usage
```bash
./LiveView.sh
```

### Interactive Controls
- **[q]** - Quit
- **[p]** - View peer details

### Configuration
Update these variables if needed:

#### Environment (USER VARIABLES)
Make sure to check and update the user variables below according to your setup:

```bash
# ─── USER VARIABLES ────────────────────────────────
CONTAINER_NAME="${CONTAINER_NAME:-midnight}"
PORT="${PORT:-9944}"
USE_DOCKER="${USE_DOCKER:-true}"
```

---

## Simple Block Monitor - Persistent Tracking

### Overview
Monitors Docker logs for new blocks and maintains a persistent `all_blocks.json` file. This data survives Docker restarts and provides long term block tracking.

### Commands

#### Start Background Monitoring
```bash
./simple_block_monitor.sh start
```
- Runs in background
- Creates `block_monitor.log` and `.block_monitor.pid`
- Continuously appends new blocks to `all_blocks.json`

#### Stop Background Monitoring
```bash
./simple_block_monitor.sh stop
```

#### Check Status
```bash
./simple_block_monitor.sh status
```
- Shows if monitor is running
- Displays current block count

#### Run Interactively
```bash
./simple_block_monitor.sh run
```
- Shows real-time output
- Press Ctrl+C to stop

### Files Created
- `all_blocks.json` - Persistent block database
- `block_monitor.log` - Monitor activity log
- `.block_monitor.pid` - Process tracking file

---

## Usage Workflows

### Option 1: Basic Monitoring
```bash
# Just run the dashboard
./LiveView.sh
```
- Shows current session blocks only
- Blocks reset on Docker restart

### Option 2: Full Persistent Monitoring (Recommended)
```bash
# Start persistent block tracking
./simple_block_monitor.sh start

# Run dashboard with historic data
./LiveView.sh
```
- Dashboard shows both historic and current blocks
- Historic count survives Docker restarts
- Continuous background monitoring

### Option 3: One-Time Check
```bash
# Check monitor status
./simple_block_monitor.sh status

# Run dashboard
./LiveView.sh
```

---

## Integration Features

When both tools are used together:

1. **Historic Blocks Line**: LiveView shows total blocks since monitoring started
2. **Persistent Data**: Block count survives Docker container restarts
3. **Duplicate Prevention**: Only truly new blocks are added to the database
4. **Automatic Integration**: LiveView automatically detects and uses `all_blocks.json`

---

## File Structure

```
full pack/
├── LiveView.sh                    # Real-time dashboard
├── simple_block_monitor.sh        # Block tracking script
├── partner-chains-public-keys.json # Required keys file
├── all_blocks.json                # Block database (created automatically)
├── block_monitor.log              # Monitor logs (created automatically)
├── .block_monitor.pid             # Process tracking (created automatically)
└── README.md                      # This file
```

---

## Troubleshooting

### LiveView Issues
**Dashboard not showing data:**
```bash
# Test RPC connection
curl -s http://127.0.0.1:9615/metrics
```
- Should return metrics data
- Update CONTAINER_NAME and PORT variables if needed

### Block Monitor Issues
**"Blocks file not found":**
- Run `./simple_block_monitor.sh start` to create `all_blocks.json`

**"Monitor already running":**
```bash
./simple_block_monitor.sh stop
./simple_block_monitor.sh start
```

**No new blocks appearing:**
- Check if node is producing blocks
- Verify container name: `docker ps`
- Check logs: `tail -f block_monitor.log`

### General Issues
**Permission denied:**
```bash
chmod +x LiveView.sh simple_block_monitor.sh
```

**Missing dependencies:**
```bash
# Ubuntu/Debian
sudo apt update && sudo apt install jq curl

# macOS
brew install jq curl
```

---

## Environment Variables

- `CONTAINER_NAME` - Docker container name (default: "midnight")
- `PORT` - RPC port (default: 9944)
- `USE_DOCKER` - Use Docker commands (default: true)

---

## Notes

- Docker logs are not persistent by default use Simple Block Monitor for long term tracking
- The dashboard refreshes every second
- Block monitor prevents duplicate entries automatically
- Both tools can run independently or together

---

## Contribute to World Development

  Please stake some ADA to `Enigma` ticker `one`. This helps us to continue building and maintaining the midnight tools.
