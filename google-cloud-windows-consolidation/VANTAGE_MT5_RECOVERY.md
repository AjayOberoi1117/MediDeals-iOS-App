# Vantage MT5 Windows recovery

## Confirmed evidence

- Windows executable discovery is resolved at
  `C:\Program Files\VIG Group MT5 Terminal\terminal64.exe`.
- Explicit-path Python initialization reached the terminal and returned
  `(-6, 'Terminal: Authorization failed')`; this is no longer an IPC/path
  discovery failure.
- Mac terminal journals on 8 and 10 August 2026 show account `25285913`
  authorized on `VantageMarkets-Demo` through access point `AS03` (terminal
  build 5660).
- The Mac terminal has an active `Bases\VantageMarkets-Demo` cache for this
  account and symbol data including EURUSD, GBPUSD, XAUUSD, and BTCUSD.

`AS03` is the access point selected behind the server display name; it is not
evidence that a different server name should be entered. With no remote path
to the Windows files, the Windows `servers.dat` and journal cannot be compared,
so stale Windows metadata (case A) versus rejected password/account state
(case B) remains unresolved. No evidence currently proves a `.srv` mismatch.

## One required Windows GUI action

In the VIG Group MT5 terminal, use **File > Login to Trade Account** once and
submit account `25285913` with server `VantageMarkets-Demo` and the already-held
password. Do not enable Algo Trading and do not place a test trade.

After that single GUI action, run the read-only check from PowerShell:

```powershell
cd C:\TradingBots
.\.venv\Scripts\python.exe .\executor\verify_mt5_connection.py
```

It reports the executable, initialization result/error, account and broker
identity, account classification, connection/trading flags, and symbol count.
It does not select symbols, validate orders, send orders, or change positions.
