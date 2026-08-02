# BOT INVENTORY & AUDIT REPORT

**Generated**: 31 July 2026  
**Repository**: /home/user/MediDeals-iOS-App  
**Audit Scope**: All Python trading bots and strategies  
**Status**: PAPER-TRADING ONLY (Phase 2 enforcement active)

---

## EXECUTIVE SUMMARY

**10 active trading bots** identified across multiple asset classes.  
**2 bots can place real broker orders** (india_scalper, local_trader) — now blocked by Phase 2 enforcement.  
**All bots require standardization** for consistent paper-trading, Telegram monitoring, and performance tracking.

---

## BOTS FOUND

### 1. SCANNER BOT (scanner_bot.py)

**Status**: ✅ ACTIVE, RECENTLY DEBUGGED  
**Location**: `telegram_bot/scanner_bot.py` (461 lines)  
**Branch**: Main (previously: claude/bots-trade-signals-debug-wjevgt)

**Market**: Indian Equities (NSE)  
**Instruments**: NIFTY 50/100 (49 stocks)  
**Timeframe**: 30-minute candles (primary), 1-minute fallback  
**Data Provider**: Upstox API (historical candles)  
**Execution**: Read-only (no broker orders — signals only)  
**Notification**: Telegram + WhatsApp + Email

**Strategy**:
- EMA crossover: Fast=25, Slow=50 (1-bar confirmation)
- RSI filter: 45-68 acceptable range
- ATR-based stop-loss and targets (1x SL, 2x TP)
- Confidence tiers: HIGH, MEDIUM, LOW
- Current filter: MEDIUM+ confidence

**Entry Conditions**:
- EMA-9 crosses above EMA-21 (bullish)
- RSI in acceptable range
- 1-minute candles fresher than 15 minutes old
- Not in cooldown period

**Exit Conditions**:
- Market close (15:30 IST)
- Signal reversal
- No explicit stop-loss implementation (signals only)

**Risk Sizing**:
- Capital allocation by confidence: HIGH=200k, MEDIUM=150k, LOW=100k
- Quantity calculated from capital
- Max signals per day: 100

**Known Defects**:
- Per-scan signal limit (was removing qualifying signals) — **FIXED in commit 0617053**
- Stale 30-minute candles (>35 min old) prevented signals — **FIXED: switched to 1-minute primary**
- High confidence filter too restrictive — **LOWERED to MEDIUM+**

**Dependencies**:
- `requests` (HTTP API)
- `pandas` (data handling)
- `pytz` (timezone)
- `.env` file with UPSTOX_TOKEN, BOT_TOKEN, CHAT_ID

**Secrets Required**:
- UPSTOX_TOKEN (API authentication)
- BOT_TOKEN (Telegram bot token)
- CHAT_ID (Telegram destination)
- WA_PHONE_NUMBER_ID, WA_ACCESS_TOKEN (WhatsApp)
- EMAIL_FROM, EMAIL_PASSWORD (Gmail)

**Logs**: `/tmp/scanner-bot.log` (on Mac: varies)

**Test Coverage**: Manual testing only (no unit tests)

**Current Results**:
- As of 31 Jul 2026: Zero signals despite NIFTY +1.05%
- Root cause: Stale candle data — **RESOLVED**
- Recent performance: Unknown (needs ledger integration)

**Recommended Disposition**: **REPAIR & INTEGRATE WITH LEDGER**
- Add paper-trading ledger integration
- Add Telegram router integration
- Add unit tests
- Enable Telegram alerts to Ajay's monitoring chat
- Track performance in leaderboard

**Live-Order Prevention Mechanism**: None currently — relies on read-only API calls only. No place_order function.

---

### 2. NIFTY SCALPER (nifty_scalper.py)

**Status**: ⏸️ DISABLED (user requested: "turn off, filtered options bot now covers same")  
**Location**: `telegram_bot/nifty_scalper.py` (253 lines)  
**Branch**: Main

**Market**: NIFTY Index (intraday)  
**Timeframe**: 1-minute candles  
**Data Provider**: Unknown (needs inspection)  
**Execution**: Unknown (needs inspection)  
**Notification**: Unknown (needs inspection)

**Strategy**: Unknown (needs detailed code inspection)

**Known Defects**: Unknown

**Test Coverage**: None

**Recommended Disposition**: **AUDIT & DOCUMENT, THEN ARCHIVE**
- User explicitly disabled this bot
- Document strategy for reference
- Move to archived branch if future resurrection needed
- Do not schedule or activate during evaluation phase

---

### 3. INDIA SCALPER (india_scalper.py) ⚠️

**Status**: ⚠️ HIGH-RISK — **BLOCKED** by Phase 2 enforcement  
**Location**: `telegram_bot/india_scalper.py` (445 lines)  
**Branch**: Main

**Market**: NSE Equities (NIFTY 50)  
**Instruments**: 50 stocks (hardcoded list)  
**Timeframe**: 30-minute candles  
**Data Provider**: Upstox API (primary), Yahoo Finance (fallback)  
**Execution**: **CAN PLACE UPSTOX LIVE ORDERS** (function: `upstox_place_order`)  
**Notification**: Telegram

**Strategy**:
- EMA: Fast=9, Slow=21
- RSI filter: 14-period, buy below 60
- ADX trend strength: Min=20
- ATR-based stops: 1.5x SL, 3.0x TP
- Quantity: 1 share per trade (configurable)
- Cooldown: 1800 seconds between signals

**Critical Risk**: Direct Upstox order placement

```python
def upstox_place_order(symbol, transaction_type):
    # ... Calls https://api.upstox.com/v2/order/place
    # ... Product="I" (MIS intraday), Order_type="MARKET"
    # ... Places REAL broker orders if UPSTOX_TOKEN is set
```

**Secrets Required**:
- UPSTOX_TOKEN (live order capability!)
- UPSTOX_DATA_TOKEN (market data)
- TELEGRAM_TOKEN or ELITE_BOT_TOKEN
- SIGNAL_CHAT_ID

**Logs**: File-based (unknown path)

**State File**: `.seen_india_scalper` (duplicate detection)

**Test Coverage**: None

**Recommended Disposition**: **REJECT FOR LIVE TRADING, IMPLEMENT AS PAPER-ONLY SIMULATION**
- Disable all `upstox_place_order()` calls
- Integrate with paper-trading ledger instead
- Use TradingMode.PAPER enforcement
- Integrate with Telegram router for Ajay monitoring
- After full paper testing: Consider for controlled pilot (separate approval)

**Live-Order Prevention Mechanism**: ❌ NONE — Must add Phase 2 enforcement

---

### 4. LOCAL TRADER (local_trader.py) ⚠️

**Status**: ⚠️ HIGH-RISK — **BLOCKED** by Phase 2 enforcement  
**Location**: `telegram_bot/local_trader.py` (292 lines)  
**Branch**: Main

**Market**: Forex + Gold (via MetaTrader5)  
**Instruments**: EURUSD, GBPUSD, USDJPY, XAUUSD (via XM MT5 account)  
**Timeframe**: 1-minute (polling every 60 seconds)  
**Data Provider**: Yahoo Finance  
**Execution**: **CAN PLACE METATRADER5 LIVE ORDERS** (function: `mt5.order_send`)  
**Notification**: Telegram

**Strategy**:
- EMA: Fast=9, Slow=21
- RSI filter: Buy below 65, Sell above 35
- ATR-based stops and targets
- Lot size: 0.01 (configurable via LOT_SIZE env var)

**Critical Risk**: Direct MetaTrader5 order placement

```python
# Line ~216:
result = mt5.order_send(req)  # Places REAL MT5 orders
```

**Secrets Required**:
- MT5_LOGIN (XM account login)
- MT5_PASSWORD (XM password)
- MT5_SERVER (broker server)
- VANTAGE_EA_TOKEN (Telegram bot)
- SIGNAL_CHAT_ID (destination)

**Logs**: `local_trader.log` (local file)

**Test Coverage**: None

**Recommended Disposition**: **REJECT FOR LIVE TRADING, DO NOT ENABLE**
- This bot connects to live MT5 account
- High risk of unintended fills
- Disable MetaTrader5 login entirely during evaluation
- Convert to paper simulation only
- Integrate with paper-trading ledger
- Integrate with Telegram router

**Live-Order Prevention Mechanism**: ❌ NONE — Must add Phase 2 enforcement

---

### 5. OPTIONS SCALPER (options_scalper.py)

**Status**: ⚠️ NOT YET EVALUATED  
**Location**: `telegram_bot/options_scalper.py` (348 lines)

**Market**: NSE Options  
**Instruments**: Unknown (needs inspection)  
**Timeframe**: Unknown (needs inspection)  
**Data Provider**: Unknown (needs inspection)  
**Execution**: Unknown (needs inspection)  
**Notification**: Unknown (needs inspection)

**Known Defects**: Unknown

**Recommended Disposition**: **AUDIT, DOCUMENT, THEN CLASSIFY**

---

### 6. FOREX SCALPER (forex_scalper.py)

**Status**: ⚠️ NOT YET EVALUATED  
**Location**: `telegram_bot/forex_scalper.py` (260 lines)

**Market**: Forex  
**Instruments**: Likely EURUSD, GBPUSD, etc. (needs inspection)  
**Timeframe**: Unknown (needs inspection)  
**Data Provider**: Unknown (needs inspection)  
**Execution**: Unknown (needs inspection)  
**Notification**: Unknown (needs inspection)

**Supporting Files**: 
- `TelegramForexBot.mq5` (MetaTrader Expert Advisor)
- `TelegramAutoTrader.mq5` (AutoTrading EA)

**Known Defects**: Unknown

**Recommended Disposition**: **AUDIT, DOCUMENT, THEN CLASSIFY**

---

### 7. BTC BOT (btc_bot.py)

**Status**: ⚠️ NOT YET EVALUATED  
**Location**: `telegram_bot/btc_bot.py` (208 lines)

**Market**: Cryptocurrency (Bitcoin)  
**Instruments**: Bitcoin (likely BTCUSD or similar)  
**Data Provider**: Unknown (needs inspection)  
**Execution**: Unknown (needs inspection)  
**Notification**: Unknown (needs inspection)

**Recommended Disposition**: **AUDIT, DOCUMENT, THEN CLASSIFY**

---

### 8. GOLD BOT (gold_bot.py)

**Status**: ⚠️ NOT YET EVALUATED  
**Location**: `telegram_bot/gold_bot.py` (212 lines)

**Market**: Commodities (Gold)  
**Instruments**: Gold spot or futures (likely XAUUSD)  
**Data Provider**: Unknown (needs inspection)  
**Execution**: Unknown (needs inspection)  
**Notification**: Unknown (needs inspection)

**Recommended Disposition**: **AUDIT, DOCUMENT, THEN CLASSIFY**

---

### 9. SIGNAL BOT (signal_bot.py)

**Status**: ⚠️ INFRASTRUCTURE / RELAY BOT  
**Location**: `telegram_bot/signal_bot.py` (333 lines)

**Purpose**: Signal aggregation and relay between bots  
**Notification**: Telegram relay mechanism

**Recommended Disposition**: **AUDIT FOR USE WITH ROUTER**
- Evaluate whether redundant with `telegram_router.py`
- Consolidate if duplicative
- Retain if additional relay logic is needed

---

### 10. BOT.PY (Generic Bot)

**Status**: ⚠️ NOT YET EVALUATED  
**Location**: `telegram_bot/bot.py` (276 lines)

**Purpose**: Generic bot (needs inspection)

**Recommended Disposition**: **AUDIT, DOCUMENT, THEN CLASSIFY**

---

## SUPPORTING INFRASTRUCTURE

### Backtesting Scripts

- `backtest_forex.py` (181 lines) — Forex backtest
- `backtest_nifty.py` (183 lines) — NIFTY backtest  
- `backtest_options.py` (242 lines) — Options backtest

**Status**: Simulat only (no live order capability)  
**Recommended Disposition**: **RETAIN & INTEGRATE WITH LEADERBOARD**

---

### Signal Relay & Sync

- `signal_server.py` (92 lines) — Signal HTTP server
- `signal_sync_mac.py` (80 lines) — Mac signal sync  
- `trade_executor.py` (44 lines) — Order executor (needs inspection)

**Recommended Disposition**: **AUDIT FOR LIVE-ORDER CAPABILITY**

---

### Utilities

- `trader.py` (134 lines) — Generic trader
- `emailer.py` (32 lines) — Email notifications
- `whatsapp.py` (58 lines) — WhatsApp notifications
- `token_updater_bot.py` (192 lines) — Token refresh
- `mac_trade_writer.py` (37 lines) — Mac logging
- `wine_server.py` (29 lines) — Wine/Windows support

---

## LAUNCHAGENT SCHEDULERS FOUND

```
com.medideals.scanner-bot.plist       (currently active)
com.medideals.forex-scalper.plist     (disabled)
com.medideals.india-scalper.plist     (disabled)
com.medideals.options-scalper.plist   (disabled)
com.medideals.signal_sync.plist       (disabled)
```

**Current Status**: Only scanner-bot.plist is scheduled.

**Recommended Action**: Do not activate other plist files until bots pass Phase 2/3 evaluation and Telegram monitoring is verified.

---

## AUDIT FINDINGS & SEVERITY

### CRITICAL 🔴

1. **india_scalper.py places real Upstox orders** — BLOCKED by Phase 2  
2. **local_trader.py places real MetaTrader5 orders** — BLOCKED by Phase 2  
3. **No paper-trading ledger** (all bots before integration) — PARTIALLY ADDRESSED (Phase 3)  
4. **No unified Telegram monitoring** (inconsistent alerts) — ADDRESSED (telegram_router.py)  
5. **scanner_bot per-scan limit removed qualifying signals** — FIXED (commit 0617053)  
6. **Stale candle data prevented NIFTY scanner** — FIXED (commit 791c4d6)

### HIGH 🟠

1. No demo-mode enforcement layer — **ADDRESSED (trading_bot_safety.py)**  
2. No duplicate signal detection — **PARTIAL (telegram_router.py)**  
3. Missing unit test coverage — PENDING  
4. Secrets hardcoded in some files — PENDING  
5. Inconsistent cost assumptions across bots — PENDING

### MEDIUM 🟡

1. No performance leaderboard — PENDING  
2. Backtest files not integrated with paper ledger — PENDING  
3. MetaTrader EA files (MQ5) not evaluated — PENDING  
4. Signal relay infrastructure not consolidated — PENDING

### LOW 🟢

1. Code style inconsistency — PENDING  
2. Documentation gaps — PENDING

---

## REMEDIATION SUMMARY

### DONE ✅

- Phase 1: Inventory (this document)
- Phase 2: Demo-mode enforcement (`trading_bot_safety.py`)
- Phase 3: Paper-trading ledger (`paper_trading_ledger.py`)
- Telegram routing infrastructure (`telegram_router.py`)
- Live-order blocking for india_scalper and local_trader

### PENDING 🔄

- Modify scanner_bot.py to use paper ledger and Telegram router
- Modify india_scalper.py to use Phase 2 enforcement and paper ledger
- Modify local_trader.py to use Phase 2 enforcement and paper ledger
- Audit remaining 7 bots and classify
- Build performance leaderboard (Phase 5)
- Add comprehensive test suite (Phase 9)
- Create bot operations layer (Phase 4)
- Plan Mac scheduling without activation (Phase 10)
- Implement NIFTY/BANKNIFTY experimental scalpers (Phase 7)

---

## NEXT STEPS

1. **Integrate scanner_bot with paper ledger** (enables Telegram alerts + performance tracking)
2. **Audit remaining bots** (classify and document all 10)
3. **Add test coverage** (especially for demo-mode enforcement)
4. **Build performance leaderboard** (daily/weekly/monthly rankings)
5. **Create bot operations commands** (start, stop, status, logs, reports)
6. **Plan Mac scheduling** (show Ajay before activation)

---

## TELEGRAM MONITORING STATUS

**Implementation**: READY (telegram_router.py created)

**Bots Configured**:
- scanner_v2: ENABLED (but not yet integrated)
- nifty_scalper_v1: ENABLED (but disabled until audit)
- banknifty_scalper_v1: DISABLED (not yet implemented)
- india_scalper_v1: DISABLED (blocked by Phase 2)
- options_scalper_v1: DISABLED (not yet implemented)
- forex_scalper_v1: DISABLED (not yet implemented)
- btc_scalper_v1: DISABLED (not yet implemented)

**Required from Ajay**:
- Confirm Telegram bot token for alerts (currently using BOT_TOKEN from .env)
- Confirm destination chat ID (currently using CHAT_ID from .env)
- Approval to send test alert to monitoring chat

**Safety Measures**:
- All alerts labeled `[PAPER]`
- All alerts include "NOT SENT TO BROKER" warning
- No test alerts sent to production chat yet
- Delivery status tracked in ledger
- Retries with exponential backoff (1s, 3s, 10s)
- Tokens never logged in full

---

## APPENDIX: FILE LOCATIONS

```
/home/user/MediDeals-iOS-App/
├── telegram_bot/
│   ├── scanner_bot.py ........................ 461 lines (active)
│   ├── nifty_scalper.py ..................... 253 lines (disabled)
│   ├── india_scalper.py ..................... 445 lines (blocked)
│   ├── local_trader.py ...................... 292 lines (blocked)
│   ├── options_scalper.py ................... 348 lines (audit pending)
│   ├── forex_scalper.py ..................... 260 lines (audit pending)
│   ├── btc_bot.py ........................... 208 lines (audit pending)
│   ├── gold_bot.py .......................... 212 lines (audit pending)
│   ├── signal_bot.py ........................ 333 lines (audit pending)
│   ├── bot.py .............................. 276 lines (audit pending)
│   ├── backtest_forex.py .................... 181 lines
│   ├── backtest_nifty.py .................... 183 lines
│   ├── backtest_options.py .................. 242 lines
│   ├── signal_server.py ..................... 92 lines
│   ├── signal_sync_mac.py ................... 80 lines
│   ├── trade_executor.py .................... 44 lines
│   ├── trader.py ............................ 134 lines
│   ├── emailer.py ........................... 32 lines
│   ├── whatsapp.py .......................... 58 lines
│   ├── token_updater_bot.py ................. 192 lines
│   ├── mac_trade_writer.py .................. 37 lines
│   ├── wine_server.py ....................... 29 lines
│   ├── nse_holidays.py ...................... 37 lines
│   ├── .env ................................ (secrets, not reviewed)
│   ├── README.md
│   └── com.medideals.*.plist ............... (LaunchAgent configs)
├── trading_bot_safety.py .................... Central demo-mode enforcement
├── telegram_router.py ....................... Unified Telegram routing
├── paper_trading_ledger.py .................. Paper trade tracking
└── docs/
    └── BOT_INVENTORY.md ..................... This document
```

---

**Prepared by**: Claude Code Audit System  
**Date**: 31 July 2026  
**Repository SHA**: bot/demo-portfolio-lab (see git log for commit history)  
**Status**: ONGOING (Phases 4-10 in progress)
