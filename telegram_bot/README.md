# Telegram Forex Bot — MT5 / Vantage (macOS + Wine)

Live currency pair rates delivered via Telegram, powered by MetaTrader 5 running under Wine on macOS.

---

## Quick Start (macOS + Wine)

### Step 1 — Install Wine & MT5

1. Install [Wine](https://www.winehq.org) or [CrossOver](https://www.codeweavers.com/crossover) on your Mac
2. Install MetaTrader 5 inside Wine and log into your **Vantage demo account**
3. Keep MT5 running (it must be open for the bridge to work)

### Step 2 — Install Python inside Wine

```bash
# Download Python 3.10 Windows installer, then:
wine msiexec /i python-3.10.11-amd64.msi

# Install required packages inside Wine Python:
wine pip install MetaTrader5 mt5linux
```

### Step 3 — Install native macOS dependencies

```bash
cd telegram_bot
pip install -r requirements.txt
```

### Step 4 — Configure `.env`

Edit `telegram_bot/.env`:

| Key | Value |
|-----|-------|
| `MT5_WINE_MODE` | `true` |
| `MT5_LOGIN` | Your Vantage demo account number |
| `MT5_PASSWORD` | Your Vantage demo password |
| `MT5_SERVER` | `Vantage-Demo` (or `Vantage-Live` for real account) |
| `ACTIVE_BOT` | `ELITE` or `STOCX` |

### Step 5 — Start the Wine bridge server

Open a Terminal and run:

```bash
wine python wine_server.py
```

Leave this terminal open. You'll see: `Starting MT5 Wine bridge server on localhost:18812 ...`

### Step 6 — Start the Telegram bot

Open a second Terminal and run:

```bash
python bot.py
```

---

## Bot Commands

| Command | Description |
|---------|-------------|
| `/rate EURUSD` | Mid price for any symbol |
| `/info EURUSD` | Full quote: bid, ask, spread, high, low |
| `/pairs` | List of common forex/CFD symbols |
| `/help` | Command reference |

---

## Vantage Server Names

| Account type | MT5_SERVER value |
|-------------|-----------------|
| Demo | `Vantage-Demo` |
| Live | `Vantage-Live` |

To confirm: open MT5 → File → Open Account → search "Vantage" → note the server name shown.

---

## Switching Bots

To run the Stocx bot instead of Elite:

```bash
ACTIVE_BOT=STOCX python bot.py
```

Or change `ACTIVE_BOT=STOCX` in `.env`.

---

## Tokens

| Bot | Environment variable |
|-----|---------------------|
| Elite | `ELITE_BOT_TOKEN` in `.env` |
| Stocx | `STOCX_BOT_TOKEN` in `.env` |
