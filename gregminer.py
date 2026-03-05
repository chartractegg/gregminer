#!/usr/bin/env python3
"""
GregMiner — Gregcoin (GRC) Wallet + Miner GUI
============================================
A single-file Python/tkinter application that lets you:
  • Connect to a running gregcoind node
  • Mine GRC blocks (CPU mining via getblocktemplate)
  • View your balance and transaction history
  • Receive GRC (show your address + QR in terminal)
  • Send GRC to another address

Requirements: Python 3.8+ (no external packages needed)

Usage:
  python3 gregminer.py

Package as single executable:
  pip install pyinstaller
  pyinstaller --onefile --windowed gregminer.py
"""

import base64
import hashlib
import json
import os
import struct
import threading
import time
import tkinter as tk
import tkinter.messagebox as msgbox
import tkinter.ttk as ttk
import urllib.error
import urllib.request
from queue import Empty, Queue

VERSION = "1.0.0"

# ─── Colour palette ────────────────────────────────────────────────────────────

C_BG     = "#0d1117"   # deep background
C_PANEL  = "#161b22"   # card background
C_BORDER = "#30363d"   # borders
C_GREEN  = "#3fb950"   # GRC green (GitHub-style)
C_YELLOW = "#d29922"   # warning / pending
C_RED    = "#f85149"   # error / stop
C_TEXT   = "#c9d1d9"   # primary text
C_MUTED  = "#8b949e"   # secondary text
C_ACCENT = "#58a6ff"   # links / highlights

FONT_MONO  = ("Courier", 10)
FONT_LABEL = ("Helvetica", 10)
FONT_H1    = ("Helvetica", 16, "bold")
FONT_H2    = ("Helvetica", 12, "bold")
FONT_BTN   = ("Helvetica", 10, "bold")

# ─── Crypto helpers ────────────────────────────────────────────────────────────

def sha256d(data: bytes) -> bytes:
    return hashlib.sha256(hashlib.sha256(data).digest()).digest()


def varint(n: int) -> bytes:
    if n < 0xfd:
        return struct.pack("<B", n)
    elif n <= 0xFFFF:
        return b"\xfd" + struct.pack("<H", n)
    elif n <= 0xFFFFFFFF:
        return b"\xfe" + struct.pack("<I", n)
    else:
        return b"\xff" + struct.pack("<Q", n)


def merkle_root(txids: list) -> bytes:
    if not txids:
        return b"\x00" * 32
    layer = list(txids)
    while len(layer) > 1:
        if len(layer) % 2 == 1:
            layer.append(layer[-1])
        layer = [sha256d(layer[i] + layer[i + 1]) for i in range(0, len(layer), 2)]
    return layer[0]


def bits_to_target(nbits_hex: str) -> int:
    nbits = int(nbits_hex, 16)
    exp = (nbits >> 24) & 0xFF
    mant = nbits & 0x007FFFFF
    return mant * (256 ** (exp - 3))


def p2pkh_script(address: str) -> bytes:
    """Decode base58check address and build P2PKH scriptPubKey."""
    ALPHABET = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"
    n = 0
    for ch in address:
        n = n * 58 + ALPHABET.index(ch)
    raw = n.to_bytes(25, "big")
    hash160 = raw[1:21]
    return b"\x76\xa9\x14" + hash160 + b"\x88\xac"


def build_coinbase(height: int, value: int, script_pubkey: bytes, extra_nonce: int) -> bytes:
    height_bytes = height.to_bytes((height.bit_length() + 8) // 8, "little")
    script_sig = bytes([len(height_bytes)]) + height_bytes
    en = extra_nonce.to_bytes(4, "little")
    script_sig += bytes([len(en)]) + en
    return (
        struct.pack("<i", 1)
        + varint(1)
        + b"\x00" * 32
        + struct.pack("<I", 0xFFFFFFFF)
        + varint(len(script_sig))
        + script_sig
        + struct.pack("<I", 0xFFFFFFFF)
        + varint(1)
        + struct.pack("<q", value)
        + varint(len(script_pubkey))
        + script_pubkey
        + struct.pack("<I", 0)
    )


# ─── RPC client ────────────────────────────────────────────────────────────────

class RPCClient:
    def __init__(self, host: str, port: int, user: str, password: str):
        self.url = f"http://{host}:{port}/"
        creds = base64.b64encode(f"{user}:{password}".encode()).decode()
        self._auth = f"Basic {creds}"
        self._id = 0

    def call(self, method: str, *params):
        self._id += 1
        body = json.dumps({"jsonrpc": "1.1", "id": self._id,
                           "method": method, "params": list(params)}).encode()
        req = urllib.request.Request(
            self.url, data=body,
            headers={"Content-Type": "application/json",
                     "Authorization": self._auth},
        )
        try:
            with urllib.request.urlopen(req, timeout=10) as r:
                resp = json.loads(r.read())
        except urllib.error.HTTPError as e:
            body = e.read()
            try:
                resp = json.loads(body)
            except Exception:
                raise RuntimeError(f"HTTP {e.code}: {body[:200]}")
        if resp.get("error"):
            raise RuntimeError(resp["error"])
        return resp["result"]


# ─── Mining engine ──────────────────────────────────────────────────────────────

def _mine_range(header76: bytes, nbits_hex: str, start: int, end: int,
                q: Queue, stop: threading.Event):
    target = bits_to_target(nbits_hex)
    hdr = bytearray(header76 + b"\x00\x00\x00\x00")
    nonce, count, t0 = start, 0, time.monotonic()
    while nonce <= end and not stop.is_set():
        struct.pack_into("<I", hdr, 76, nonce)
        val = int.from_bytes(sha256d(bytes(hdr))[::-1], "big")
        if val < target:
            q.put(("found", nonce, sha256d(bytes(hdr))[::-1].hex()))
            return
        nonce += 1
        count += 1
        if count % 10_000 == 0:
            elapsed = time.monotonic() - t0
            q.put(("hashrate", count / elapsed if elapsed else 0))
    q.put(("exhausted",))


class MinerEngine:
    def __init__(self, rpc: RPCClient, address: str, callback):
        self.rpc = rpc
        self.address = address
        self.callback = callback
        self._stop = threading.Event()
        self._extra_nonce = 0
        self.running = False
        self.hashrate = 0.0

    def start(self):
        self._stop.clear()
        self.running = True
        threading.Thread(target=self._loop, daemon=True).start()

    def stop(self):
        self._stop.set()
        self.running = False

    def _loop(self):
        while not self._stop.is_set():
            try:
                tmpl = self.rpc.call("getblocktemplate", {"rules": ["segwit"]})
            except Exception as e:
                self.callback("error", str(e))
                time.sleep(5)
                continue

            self._extra_nonce += 1
            try:
                header76, before_hex, after_hex = self._build(tmpl)
            except Exception as e:
                self.callback("error", f"build: {e}")
                time.sleep(2)
                continue

            q: Queue = Queue()
            t = threading.Thread(
                target=_mine_range,
                args=(header76, tmpl["bits"], 0, 0xFFFFFFFF, q, self._stop),
                daemon=True,
            )
            t.start()

            while t.is_alive() or not q.empty():
                try:
                    msg = q.get(timeout=0.2)
                except Empty:
                    continue
                kind = msg[0]
                if kind == "found":
                    nonce, blk_hash = msg[1], msg[2]
                    block_hex = before_hex + struct.pack("<I", nonce).hex() + after_hex
                    try:
                        self.rpc.call("submitblock", block_hex)
                        self.callback("block_found", blk_hash)
                    except Exception as e:
                        self.callback("error", f"submit: {e}")
                    break
                elif kind == "hashrate":
                    self.hashrate = msg[1]
                    self.callback("hashrate", msg[1])
                elif kind == "exhausted":
                    break

    def _build(self, tmpl):
        addr_script = p2pkh_script(self.address)
        cb = build_coinbase(tmpl["height"], tmpl["coinbasevalue"],
                            addr_script, self._extra_nonce)
        txids = [sha256d(cb)]
        txdata = [cb]
        for tx in tmpl.get("transactions", []):
            txdata.append(bytes.fromhex(tx["data"]))
            txids.append(bytes.fromhex(tx["txid"])[::-1])

        mr = merkle_root(txids)
        prev = bytes.fromhex(tmpl["previousblockhash"])[::-1]
        header76 = (
            struct.pack("<I", tmpl["version"])
            + prev
            + mr
            + struct.pack("<I", tmpl["curtime"])
            + bytes.fromhex(tmpl["bits"])[::-1]
        )
        assert len(header76) == 76
        suffix = varint(len(txdata)) + b"".join(txdata)
        return header76, header76.hex(), suffix.hex()


# ─── Reusable UI helpers ────────────────────────────────────────────────────────

def styled_btn(parent, text, command, color=C_GREEN, fg="black", **kw):
    return tk.Button(
        parent, text=text, command=command,
        bg=color, fg=fg, activebackground=color,
        font=FONT_BTN, relief="flat", cursor="hand2",
        padx=12, pady=4, **kw,
    )


def card(parent, title="", **kw):
    f = tk.LabelFrame(parent, text=title, bg=C_PANEL, fg=C_MUTED,
                      font=FONT_LABEL, bd=1, relief="solid",
                      highlightbackground=C_BORDER, **kw)
    return f


def label_row(parent, row, key, default="—", label_width=16):
    tk.Label(parent, text=key + ":", bg=C_PANEL, fg=C_MUTED,
             font=FONT_LABEL, width=label_width, anchor="e"
             ).grid(row=row, column=0, padx=(8, 4), pady=3, sticky="e")
    v = tk.Label(parent, text=default, bg=C_PANEL, fg=C_TEXT,
                 font=FONT_MONO, anchor="w")
    v.grid(row=row, column=1, padx=(4, 8), pady=3, sticky="w")
    return v


def entry_row(parent, row, key, default="", show="", label_width=16, entry_width=32):
    tk.Label(parent, text=key + ":", bg=C_PANEL, fg=C_MUTED,
             font=FONT_LABEL, width=label_width, anchor="e"
             ).grid(row=row, column=0, padx=(8, 4), pady=4, sticky="e")
    var = tk.StringVar(value=default)
    tk.Entry(parent, textvariable=var, show=show, width=entry_width,
             bg=C_BG, fg=C_TEXT, insertbackground=C_TEXT,
             relief="flat", bd=4, font=FONT_MONO,
             ).grid(row=row, column=1, padx=(4, 8), pady=4, sticky="w")
    return var


# ─── Main application ───────────────────────────────────────────────────────────

class GregMiner(tk.Tk):
    def __init__(self):
        super().__init__()
        self.title(f"GregMiner v{VERSION} — Gregcoin (GRC)")
        self.configure(bg=C_BG)
        self.minsize(700, 580)

        self.rpc: RPCClient | None = None
        self.engine: MinerEngine | None = None
        self._blocks_found = 0
        self._mine_start: float | None = None

        self._build_header()
        self._build_tabs()
        self._poll()

    # ── Header ─────────────────────────────────────────────────────────────────

    def _build_header(self):
        hdr = tk.Frame(self, bg="#0f6b35", pady=10)
        hdr.pack(fill="x")
        tk.Label(hdr, text="⛏  GregMiner", font=FONT_H1,
                 bg="#0f6b35", fg=C_GREEN).pack(side="left", padx=16)
        self._status_dot = tk.Label(hdr, text="●  Disconnected",
                                    font=FONT_LABEL, bg="#0f6b35", fg=C_RED)
        self._status_dot.pack(side="right", padx=16)

    # ── Tabs ───────────────────────────────────────────────────────────────────

    def _build_tabs(self):
        nb = ttk.Notebook(self)
        nb.pack(fill="both", expand=True, padx=0, pady=0)

        style = ttk.Style()
        style.theme_use("default")
        style.configure("TNotebook", background=C_BG, borderwidth=0)
        style.configure("TNotebook.Tab", background=C_PANEL, foreground=C_MUTED,
                        padding=[14, 6], font=FONT_LABEL)
        style.map("TNotebook.Tab",
                  background=[("selected", C_BG)],
                  foreground=[("selected", C_GREEN)])

        self._tab_connect  = self._make_tab(nb, "🔌  Connect")
        self._tab_wallet   = self._make_tab(nb, "💰  Wallet")
        self._tab_miner    = self._make_tab(nb, "⛏  Miner")
        self._tab_txs      = self._make_tab(nb, "📋  History")
        self._tab_about    = self._make_tab(nb, "ℹ  About")

        self._build_connect_tab()
        self._build_wallet_tab()
        self._build_miner_tab()
        self._build_txs_tab()
        self._build_about_tab()

    def _make_tab(self, nb, title):
        f = tk.Frame(nb, bg=C_BG)
        nb.add(f, text=title)
        return f

    # ── Connect tab ────────────────────────────────────────────────────────────

    def _build_connect_tab(self):
        outer = tk.Frame(self._tab_connect, bg=C_BG)
        outer.pack(expand=True, fill="both", padx=40, pady=30)

        tk.Label(outer, text="Node Connection", font=FONT_H2,
                 bg=C_BG, fg=C_TEXT).pack(anchor="w", pady=(0, 10))
        tk.Label(outer, text="Enter the details for your running gregcoind node.",
                 font=FONT_LABEL, bg=C_BG, fg=C_MUTED).pack(anchor="w", pady=(0, 16))

        c = card(outer)
        c.pack(fill="x")

        self._cv_host = entry_row(c, 0, "Host",     "127.0.0.1")
        self._cv_port = entry_row(c, 1, "RPC Port", "8445")
        self._cv_user = entry_row(c, 2, "User",     "grcuser")
        self._cv_pass = entry_row(c, 3, "Password", "", show="*")

        tk.Label(c, text="(These match your gregcoin.conf rpcuser/rpcpassword)",
                 bg=C_PANEL, fg=C_MUTED, font=("Helvetica", 9)).grid(
            row=4, column=0, columnspan=2, pady=(0, 8))

        btn_row = tk.Frame(outer, bg=C_BG)
        btn_row.pack(pady=16, anchor="w")
        styled_btn(btn_row, "Connect", self._do_connect).pack(side="left", padx=(0, 8))

        self._conn_info = tk.Label(outer, text="", bg=C_BG, fg=C_MUTED,
                                   font=FONT_MONO, justify="left", wraplength=520)
        self._conn_info.pack(anchor="w")

        conf_card = card(outer, title="Quick Setup — gregcoin.conf")
        conf_card.pack(fill="x", pady=(24, 0))
        conf_text = (
            "server=1\n"
            "rpcuser=grcuser\n"
            "rpcpassword=yourpassword\n"
            "rpcallowip=127.0.0.1\n"
            "rpcport=8445"
        )
        conf_box = tk.Text(conf_card, height=5, bg=C_BG, fg=C_ACCENT,
                           font=FONT_MONO, relief="flat", bd=4)
        conf_box.insert("1.0", conf_text)
        conf_box.config(state="disabled")
        conf_box.pack(fill="x", padx=8, pady=8)

    def _do_connect(self):
        try:
            rpc = RPCClient(self._cv_host.get(), int(self._cv_port.get()),
                            self._cv_user.get(), self._cv_pass.get())
            info = rpc.call("getblockchaininfo")
            self.rpc = rpc
            chain = info["chain"]
            blocks = info["blocks"]
            difficulty = info.get("difficulty", "?")
            self._conn_info.config(
                fg=C_GREEN,
                text=f"✓  Connected!\n"
                     f"Chain: {chain}   Height: {blocks}   "
                     f"Difficulty: {difficulty:.4f}",
            )
            self._status_dot.config(text=f"●  {chain}:{blocks}", fg=C_GREEN)
            self._refresh_wallet()
        except Exception as e:
            self._conn_info.config(fg=C_RED, text=f"✗  {e}")
            self._status_dot.config(text="●  Error", fg=C_RED)

    # ── Wallet tab ─────────────────────────────────────────────────────────────

    def _build_wallet_tab(self):
        outer = tk.Frame(self._tab_wallet, bg=C_BG)
        outer.pack(expand=True, fill="both", padx=40, pady=20)

        # Balance card
        bal_card = card(outer, "Balance")
        bal_card.pack(fill="x", pady=(0, 16))
        self._wl_balance     = label_row(bal_card, 0, "Confirmed")
        self._wl_unconfirmed = label_row(bal_card, 1, "Unconfirmed")
        self._wl_total       = label_row(bal_card, 2, "Total")
        styled_btn(bal_card, "Refresh", self._refresh_wallet,
                   ).grid(row=3, column=0, columnspan=2, pady=8)

        # Receive card
        rcv_card = card(outer, "Receive GRC")
        rcv_card.pack(fill="x", pady=(0, 16))
        self._wl_address = label_row(rcv_card, 0, "Your Address", label_width=14)
        self._wl_address.config(font=FONT_MONO, fg=C_ACCENT, cursor="hand2")
        self._wl_address.bind("<Button-1>", self._copy_address)
        tk.Label(rcv_card, text="(click address to copy)",
                 bg=C_PANEL, fg=C_MUTED, font=("Helvetica", 9)
                 ).grid(row=1, column=0, columnspan=2, pady=(0, 4))
        styled_btn(rcv_card, "New Address", self._new_address,
                   color=C_ACCENT, fg="white"
                   ).grid(row=2, column=0, columnspan=2, pady=8)

        # Send card
        snd_card = card(outer, "Send GRC")
        snd_card.pack(fill="x")
        self._sv_to     = entry_row(snd_card, 0, "To Address", label_width=12, entry_width=44)
        self._sv_amount = entry_row(snd_card, 1, "Amount (GRC)", label_width=12, entry_width=16)
        self._sv_fee    = entry_row(snd_card, 2, "Fee (GRC)", "0.0001", label_width=12, entry_width=16)
        btn_send = styled_btn(snd_card, "Send  ➤", self._do_send,
                              color=C_YELLOW, fg="black")
        btn_send.grid(row=3, column=0, columnspan=2, pady=10)
        self._send_result = tk.Label(snd_card, text="", bg=C_PANEL, fg=C_MUTED,
                                     font=FONT_MONO, wraplength=480)
        self._send_result.grid(row=4, column=0, columnspan=2, pady=(0, 8))

    def _refresh_wallet(self):
        if not self.rpc:
            return
        try:
            # Ensure a wallet exists
            wallets = self.rpc.call("listwallets")
            if not wallets:
                self.rpc.call("createwallet", "default")
            bal   = self.rpc.call("getbalance")
            ubal  = self.rpc.call("getunconfirmedbalance")
            total = bal + ubal
            self._wl_balance.config(text=f"{bal:.8f} GRC", fg=C_GREEN)
            self._wl_unconfirmed.config(text=f"{ubal:.8f} GRC",
                                        fg=C_YELLOW if ubal else C_MUTED)
            self._wl_total.config(text=f"{total:.8f} GRC", fg=C_TEXT)
            addr = self.rpc.call("getnewaddress")
            self._wl_address.config(text=addr)
            self._current_address = addr
        except Exception as e:
            self._wl_balance.config(text=f"Error: {e}", fg=C_RED)

    def _new_address(self):
        if not self.rpc:
            msgbox.showwarning("Not connected", "Connect to a node first.")
            return
        try:
            addr = self.rpc.call("getnewaddress")
            self._wl_address.config(text=addr)
            self._current_address = addr
            self.clipboard_clear()
            self.clipboard_append(addr)
        except Exception as e:
            msgbox.showerror("Error", str(e))

    def _copy_address(self, _event=None):
        addr = getattr(self, "_current_address", "")
        if addr:
            self.clipboard_clear()
            self.clipboard_append(addr)
            self._send_result.config(text="Address copied to clipboard!", fg=C_GREEN)

    def _do_send(self):
        if not self.rpc:
            msgbox.showwarning("Not connected", "Connect to a node first.")
            return
        to = self._sv_to.get().strip()
        try:
            amount = float(self._sv_amount.get())
            fee    = float(self._sv_fee.get())
        except ValueError:
            self._send_result.config(text="Invalid amount or fee.", fg=C_RED)
            return
        if not to:
            self._send_result.config(text="Enter a destination address.", fg=C_RED)
            return
        if not msgbox.askyesno("Confirm Send",
                               f"Send {amount:.8f} GRC to\n{to}\n\nFee: {fee:.8f} GRC\n\nProceed?"):
            return
        try:
            self.rpc.call("settxfee", fee)
            txid = self.rpc.call("sendtoaddress", to, amount)
            self._send_result.config(
                text=f"✓  Sent!\nTXID: {txid}", fg=C_GREEN)
            self._refresh_wallet()
        except Exception as e:
            self._send_result.config(text=f"✗  {e}", fg=C_RED)

    # ── Miner tab ──────────────────────────────────────────────────────────────

    def _build_miner_tab(self):
        outer = tk.Frame(self._tab_miner, bg=C_BG)
        outer.pack(expand=True, fill="both", padx=40, pady=20)

        # Config
        cfg = card(outer, "Mining Configuration")
        cfg.pack(fill="x", pady=(0, 12))
        self._mv_addr = entry_row(cfg, 0, "Mining Address",
                                  label_width=16, entry_width=46)
        tk.Label(cfg, text="Leave blank to auto-generate from your wallet",
                 bg=C_PANEL, fg=C_MUTED, font=("Helvetica", 9)
                 ).grid(row=1, column=0, columnspan=2, pady=(0, 6))

        # Stats
        stats = card(outer, "Live Stats")
        stats.pack(fill="x", pady=(0, 12))
        self._ml_hashrate = label_row(stats, 0, "Hash Rate")
        self._ml_blocks   = label_row(stats, 1, "Blocks Found")
        self._ml_uptime   = label_row(stats, 2, "Uptime")
        self._ml_status   = label_row(stats, 3, "Status", "Stopped")
        self._ml_status.config(fg=C_RED)

        # Controls
        ctrl = tk.Frame(outer, bg=C_BG)
        ctrl.pack(anchor="w", pady=(0, 12))
        self._btn_start = styled_btn(ctrl, "▶  Start Mining", self._start_mining)
        self._btn_start.pack(side="left", padx=(0, 8))
        self._btn_stop = styled_btn(ctrl, "◼  Stop", self._stop_mining,
                                    color=C_RED, fg="white", state="disabled")
        self._btn_stop.pack(side="left")

        # Log
        log = card(outer, "Log")
        log.pack(fill="both", expand=True)
        self._log_box = tk.Text(log, height=8, bg=C_BG, fg=C_TEXT,
                                font=FONT_MONO, state="disabled",
                                insertbackground=C_TEXT, relief="flat", bd=4)
        sb = tk.Scrollbar(log, command=self._log_box.yview, bg=C_BG)
        self._log_box.config(yscrollcommand=sb.set)
        sb.pack(side="right", fill="y")
        self._log_box.pack(fill="both", expand=True, padx=4, pady=4)

    def _start_mining(self):
        if not self.rpc:
            msgbox.showwarning("Not connected", "Connect to a node first.")
            return
        addr = self._mv_addr.get().strip()
        if not addr:
            try:
                wallets = self.rpc.call("listwallets")
                if not wallets:
                    self.rpc.call("createwallet", "default")
                addr = self.rpc.call("getnewaddress")
                self._mv_addr.set(addr)
                self._log(f"Auto address: {addr}")
            except Exception as e:
                self._log(f"ERROR: {e}")
                return
        self._blocks_found = 0
        self._mine_start = time.monotonic()
        self.engine = MinerEngine(self.rpc, addr, self._engine_cb)
        self.engine.start()
        self._btn_start.config(state="disabled")
        self._btn_stop.config(state="normal")
        self._ml_status.config(text="Mining …", fg=C_GREEN)
        self._log("Mining started")

    def _stop_mining(self):
        if self.engine:
            self.engine.stop()
            self.engine = None
        self._btn_start.config(state="normal")
        self._btn_stop.config(state="disabled")
        self._ml_status.config(text="Stopped", fg=C_RED)
        self._log("Mining stopped")

    def _engine_cb(self, kind, data=None):
        if kind == "block_found":
            self._blocks_found += 1
            self._log(f"🎉 BLOCK FOUND! {data[:20]}…")
        elif kind == "error":
            self._log(f"ERROR: {data}")

    def _log(self, msg: str):
        ts = time.strftime("%H:%M:%S")
        self._log_box.config(state="normal")
        self._log_box.insert("end", f"[{ts}] {msg}\n")
        self._log_box.see("end")
        self._log_box.config(state="disabled")

    # ── Transaction History tab ────────────────────────────────────────────────

    def _build_txs_tab(self):
        outer = tk.Frame(self._tab_txs, bg=C_BG)
        outer.pack(expand=True, fill="both", padx=20, pady=16)

        ctrl = tk.Frame(outer, bg=C_BG)
        ctrl.pack(fill="x", pady=(0, 8))
        tk.Label(ctrl, text="Recent Transactions", font=FONT_H2,
                 bg=C_BG, fg=C_TEXT).pack(side="left")
        styled_btn(ctrl, "Refresh", self._refresh_txs,
                   color=C_ACCENT, fg="white").pack(side="right")

        cols = ("time", "type", "amount", "confirmations", "txid")
        self._tx_tree = ttk.Treeview(outer, columns=cols, show="headings", height=18)
        style = ttk.Style()
        style.configure("Treeview", background=C_PANEL, foreground=C_TEXT,
                        fieldbackground=C_PANEL, rowheight=24,
                        font=FONT_MONO)
        style.configure("Treeview.Heading", background=C_BG, foreground=C_MUTED,
                        font=FONT_LABEL)
        style.map("Treeview", background=[("selected", C_ACCENT)])

        for col, width, anchor in [
            ("time",          140, "w"),
            ("type",           70, "c"),
            ("amount",        120, "e"),
            ("confirmations",  90, "c"),
            ("txid",          280, "w"),
        ]:
            self._tx_tree.heading(col, text=col.capitalize())
            self._tx_tree.column(col, width=width, anchor=anchor)

        sb = tk.Scrollbar(outer, command=self._tx_tree.yview, bg=C_BG)
        self._tx_tree.config(yscrollcommand=sb.set)
        sb.pack(side="right", fill="y")
        self._tx_tree.pack(fill="both", expand=True)

    def _refresh_txs(self):
        if not self.rpc:
            return
        try:
            txs = self.rpc.call("listtransactions", "*", 50, 0, True)
            self._tx_tree.delete(*self._tx_tree.get_children())
            for tx in reversed(txs):
                t = time.strftime("%Y-%m-%d %H:%M", time.localtime(tx.get("time", 0)))
                cat = tx.get("category", "?")
                amt = tx.get("amount", 0)
                conf = tx.get("confirmations", 0)
                txid = tx.get("txid", "")[:32] + "…"
                color = "receive" if amt >= 0 else "send"
                tag = "green" if amt >= 0 else "red"
                self._tx_tree.insert("", "end",
                    values=(t, cat, f"{amt:+.8f} GRC", conf, txid),
                    tags=(tag,))
            self._tx_tree.tag_configure("green", foreground=C_GREEN)
            self._tx_tree.tag_configure("red",   foreground=C_RED)
        except Exception as e:
            pass  # No wallet loaded yet

    # ── About tab ──────────────────────────────────────────────────────────────

    def _build_about_tab(self):
        outer = tk.Frame(self._tab_about, bg=C_BG)
        outer.pack(expand=True, fill="both", padx=60, pady=40)

        tk.Label(outer, text="⛏  GregMiner", font=("Helvetica", 24, "bold"),
                 bg=C_BG, fg=C_GREEN).pack()
        tk.Label(outer, text=f"Version {VERSION}  |  Gregcoin (GRC) Wallet + Miner",
                 font=FONT_LABEL, bg=C_BG, fg=C_MUTED).pack(pady=4)

        tk.Frame(outer, bg=C_BORDER, height=1).pack(fill="x", pady=20)

        info = [
            ("Ticker",        "GRC"),
            ("Total Supply",  "42,000,000 GRC"),
            ("Block Reward",  "100 GRC (halves every 210,000 blocks)"),
            ("Block Time",    "2.5 minutes"),
            ("Address Prefix","G"),
            ("Mainnet Port",  "8444"),
            ("RPC Port",      "8445"),
        ]
        tbl = tk.Frame(outer, bg=C_BG)
        tbl.pack()
        for i, (k, v) in enumerate(info):
            tk.Label(tbl, text=k + ":", bg=C_BG, fg=C_MUTED,
                     font=FONT_LABEL, width=18, anchor="e"
                     ).grid(row=i, column=0, padx=8, pady=2, sticky="e")
            tk.Label(tbl, text=v, bg=C_BG, fg=C_TEXT,
                     font=FONT_MONO, anchor="w"
                     ).grid(row=i, column=1, padx=8, pady=2, sticky="w")

        tk.Frame(outer, bg=C_BORDER, height=1).pack(fill="x", pady=20)
        tk.Label(outer, text="A fun project. Not financial advice. Mine responsibly.",
                 font=("Helvetica", 9, "italic"), bg=C_BG, fg=C_MUTED).pack()

    # ── Periodic refresh ───────────────────────────────────────────────────────

    def _poll(self):
        if self.engine and self.engine.running:
            r = self.engine.hashrate
            if r >= 1e6:
                rate_str = f"{r/1e6:.2f} MH/s"
            elif r >= 1e3:
                rate_str = f"{r/1e3:.1f} KH/s"
            else:
                rate_str = f"{r:.0f} H/s"
            self._ml_hashrate.config(text=rate_str, fg=C_GREEN)
            self._ml_blocks.config(text=str(self._blocks_found))
            if self._mine_start:
                e = int(time.monotonic() - self._mine_start)
                h, m, s = e // 3600, (e % 3600) // 60, e % 60
                self._ml_uptime.config(text=f"{h:02d}:{m:02d}:{s:02d}")

        self.after(2000, self._poll)


# ─── Entry point ───────────────────────────────────────────────────────────────

if __name__ == "__main__":
    app = GregMiner()
    app.mainloop()
