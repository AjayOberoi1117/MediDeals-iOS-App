# Telegram Forex Bot — MT5 / Vantage

Live currency pair rates delivered via Telegram, powered by MetaTrader 5.

## Setup

### 1. Install dependencies

```bash
cd telegram_bot
pip install -r requirements.txt
```

### 2. Configure `.env`

Edit `telegram_bot/.env`:

| Key | Description |
|-----|-------------|
| `ACTIVE_BOT` | `ELITE` or `STOCX` — which bot token to use |
| `MT5_LOGIN` | Your Vantage MT5 account number |
| `MT5_PASSWORD` | Your Vantage MT5 password |
| `MT5_SERVER` | Vantage server name (e.g. `Vantage-Live` or `Vantage-Demo`) |
| `FALLBACK_API_KEY` | Optional — free key from exchangerate-api.com for when MT5 is offline |

### 3. Run the bot

```bash
python bot.py
```

To run the Stocx bot instead:
```bash
ACTIVE_BOT=STOCX python bot.py
```

## Commands

| Command | Description |
|---------|-------------|
| `/rate EURUSD` | Mid price for any symbol |
| `/info EURUSD` | Full quote: bid, ask, spread, high, low |
| `/pairs` | List of common forex/CFD symbols |
| `/help` | Command reference |

## MT5 Requirement

The `MetaTrader5` Python package **only runs on Windows** (64-bit) with MT5 terminal installed and running. On Linux/Mac the bot automatically falls back to a free exchange-rate API (standard FX pairs only — no gold, indices, or crypto CFDs).

To find your Vantage server name: open MT5 → File → Open Account → search "Vantage".

## Tokens

| Bot | Token |
|-----|-------|
| Elite | set in `.env` as `ELITE_BOT_TOKEN` |
| Stocx | set in `.env` as `STOCX_BOT_TOKEN` |
