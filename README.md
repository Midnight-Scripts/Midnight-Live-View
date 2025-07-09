# LiveView.sh

### Inspired by CNTool's gLiveView  
#### Tested on Midnight Validator Node - Testnet - Version: 0.12.0-cab67f3b

**LiveView.sh** (version 0.12.0) is a simple script that allows users to monitor key information about their Midnight node. Currently, it displays:

- Node Version
- Server Uptime
- Container Start Time
- Node Key (partially masked for security)
- Port
- Key Status
- Registration Status
- Node Block Count (since Docker restart)
- Epoch Number
- Node Sync Status
- Peer Count
- Hardware Resources

<img width="517" alt="liveview" src="https://github.com/user-attachments/assets/e9c154bc-4ac3-4a3f-90d1-964e10a43a1e" />


---

## Prerequisites

1. Make sure you have `partner-chains-public-keys.json` in the **same directory** as this script.

2. To enable external RPC access and Prometheus metrics, update your `.envrc` file:

**Modify the `APPEND_ARGS` line as follows:**

**From:**
```bash
export APPEND_ARGS="--allow-private-ip --pool-limit 10 --trie-cache-size 0 --prometheus-external --rpc-external"
```
**To:**
```bash
export APPEND_ARGS="--validator --allow-private-ip --pool-limit 10 --trie-cache-size 0 --prometheus-external --unsafe-rpc-external --rpc-methods=Unsafe --rpc-cors all"
```

This configuration enables external RPC access and Prometheus metrics.

---

## Installation & Usage

To download and run LiveView.sh, follow these steps:

```bash
wget -O ./LiveView.sh  https://raw.githubusercontent.com/Midnight-Scripts/Midnight-Live-View/refs/heads/main/LiveView.sh
sudo chmod +x LiveView.sh
./LiveView.sh
```

---

## User Variables

If you change the Docker container name or port, update the corresponding variables in the script.  
By default, the script assumes:

```bash
CONTAINER_NAME="midnight"
PORT=9944
```

---

## Note

Docker logs are not persisted by default. If you restart the Docker container, all previous log entries are lost. As a result, the block count resets and will only reflect blocks minted after the restart.

---

## Troubleshooting

To check if the script is working for you, run the following curl command. If you see metric output, your setup is likely correct. Just be sure to update the user variables if you’re not using the default settings.

```bash
curl -s http://127.0.0.1:9615/metrics
```

---

## Contributing

Pull requests are welcome!
