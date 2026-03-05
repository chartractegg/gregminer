# GregMiner ⛏

A Gregcoin (GRC) wallet + miner in a single desktop app — no command line needed.

## Download

**[⬇ Get the latest release →](https://github.com/chartractegg/gregminer/releases/latest)**

| Platform | File | Instructions |
|----------|------|-------------|
| 🪟 Windows | `GregMiner-Windows.zip` | Extract, double-click `GregMiner.exe` |
| 🍎 macOS | `GregMiner-macOS.dmg` | Open, drag to Applications, double-click |
| 🐧 Linux | `GregMiner-Linux.tar.gz` | Extract, run `./GregMiner` |

> No Python or other software required — just download and run.

---

## Features

| Tab | What it does |
|-----|-------------|
| 🔌 Connect | Enter your gregcoind node's RPC details |
| 💰 Wallet | Check balance, copy receive address, send GRC |
| ⛏ Miner | Start/stop CPU mining with live hashrate + block counter |
| 📋 History | Browse recent transactions |
| ℹ About | Gregcoin network parameters |

---

## You'll also need: gregcoind

GregMiner is a GUI frontend — it connects to a running Gregcoin node.

Download Gregcoin Core from **[chartractegg/gregcoin](https://github.com/chartractegg/gregcoin)** and follow its setup instructions.

Quick node config (`~/.gregcoin/gregcoin.conf`):

```ini
server=1
rpcuser=grcuser
rpcpassword=yourpassword
rpcallowip=127.0.0.1
rpcport=8445
```

Start it:

```sh
gregcoind -daemon
```

Then open GregMiner → Connect tab → fill in the same user/password → **Connect**.

---

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

---

## Building from Source

```sh
# Requires Python 3.8+
python3 gregminer.py

# Build a standalone executable
pip install pyinstaller
pyinstaller --onefile --windowed --name GregMiner gregminer.py
```

## License

MIT
