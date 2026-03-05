# GregMiner ⛏

A single-file Python GUI for **Gregcoin (GRC)** — mine blocks and manage your wallet from one clean window.

![GregMiner Screenshot](docs/screenshot.png)

## Features

| Tab | What it does |
|-----|-------------|
| 🔌 Connect | Enter your node's RPC details and connect |
| 💰 Wallet | Check balance, copy your receive address, send GRC |
| ⛏ Miner | Start/stop CPU mining with live hashrate + block counter |
| 📋 History | Browse recent transactions |
| ℹ About | Gregcoin network parameters |

## Requirements

- Python 3.8+
- A running `gregcoind` node (see [Gregcoin](https://github.com/chartractegg/gregcoin))
- **No external packages** — uses only Python stdlib

## Quick Start

### 1. Set up your gregcoind node

Create `~/.gregcoin/gregcoin.conf` (or `%APPDATA%\Gregcoin\gregcoin.conf` on Windows):

```ini
server=1
rpcuser=grcuser
rpcpassword=yourpassword
rpcallowip=127.0.0.1
rpcport=8445
```

Start the node:

```sh
gregcoind -daemon
# or for regtest (local testing):
gregcoind -regtest -daemon
```

### 2. Run GregMiner

```sh
python3 gregminer.py
```

- Go to the **Connect** tab, fill in your RPC details, and hit **Connect**.
- Go to **Wallet** to see your balance and addresses.
- Go to **Miner** and click **Start Mining**!

## Building a Standalone Executable

```sh
pip install pyinstaller
pyinstaller --onefile --windowed --name GregMiner gregminer.py
# Output: dist/GregMiner  (or dist/GregMiner.exe on Windows)
```

The resulting binary runs on any machine — no Python needed.

## Gregcoin Network Parameters

| Parameter | Value |
|-----------|-------|
| Ticker | GRC |
| Total Supply | 42,000,000 GRC |
| Block Reward | 100 GRC |
| Halving Interval | Every 210,000 blocks |
| Block Time | 2.5 minutes |
| Address Prefix | G |
| Mainnet Port | 8444 |
| RPC Port | 8445 |

## How Mining Works

GregMiner uses Bitcoin's `getblocktemplate` protocol to fetch candidate blocks from your node, then searches for a valid proof-of-work nonce using Python's `hashlib`. It submits found blocks via `submitblock`. All mining runs in a background thread so the GUI stays responsive.

> ⚠️ CPU mining is for fun and testing. Gregcoin's difficulty is tuned for small clusters of Raspberry Pis.

## License

MIT
