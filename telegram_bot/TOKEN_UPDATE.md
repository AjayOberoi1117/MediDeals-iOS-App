# Token Update Instructions

## Issue Identified
The bot encountered a `UnicodeEncodeError` when trying to connect to Upstox API. This typically means:
1. The token contains invalid characters, OR
2. The token has expired

## Solution
Follow these steps to update with a fresh token:

### Step 1: Generate New Token
1. Log into your Upstox account
2. Go to Settings → API → Generate Access Token
3. Copy the complete JWT token (looks like: `eyJ0eXAi...`)

### Step 2: Create or Update .env File
On your Mac, create a file at:
```
/Users/ajayoberoi/MediDeals-iOS-App/telegram_bot/.env
```

Add the following lines:
```
UPSTOX_TOKEN=your_new_token_here_paste_complete_jwt
TELEGRAM_BOT_TOKEN=8953646046:AAF6flZRLHG7KU1JiagA48gJLcKZV7RuxKs
TELEGRAM_CHAT_ID=7093601171
```

### Step 3: Test the Token
Run the diagnostic test on your Mac:
```bash
cd /Users/ajayoberoi/MediDeals-iOS-App
python3 telegram_bot/test_api.py
```

Expected output:
```
1. TOKEN VALIDATION
   ✓ Token is valid ASCII

2. API CONNECTION TEST
   a) Fetching 30-minute candles...
      Status: 200
      Candles fetched: XX
      ✓ Data is relatively fresh
```

### Step 4: Restart Bot
After updating the token:
1. Kill the running bot if it's active
2. Restart it using the LaunchAgent or manually run:
   ```bash
   cd /Users/ajayoberoi/MediDeals-iOS-App
   python3 telegram_bot/scanner_bot.py
   ```

## Updates Made to Bot

### 1. Automatic 1-Minute Fallback
- Bot now detects when 30-minute candles are stale (>35 minutes old)
- Automatically fetches 1-minute candles for real-time signals
- This fixes the "no signals despite bullish market" issue

### 2. Better Error Messages
- Specific error handling for token encoding issues
- Clearer diagnostics when API fails
- Debug output shows which candle interval is being used

### 3. Staleness Detection
- Checks timestamp of latest candle
- Rejects data older than 35 minutes for 30-minute interval
- Ensures signals are based on current market data

## Troubleshooting

**If test_api.py shows "Token contains non-ASCII characters":**
- The token was corrupted during copy/paste
- Regenerate from Upstox and carefully paste the entire JWT without extra spaces

**If test_api.py shows "API error 401/403":**
- Token has expired
- Regenerate a new token from Upstox

**If bot still shows zero signals:**
- Run test_api.py to confirm data is fresh
- Check bot logs: `tail -f /tmp/scanner-bot.log`
- Look for "Stale data" warnings or API errors
