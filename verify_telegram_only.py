#!/usr/bin/env python3
"""
Standalone verification script for Telegram-only notification changes.
No external dependencies required - performs static code analysis only.
"""

import os
import sys
import py_compile

def verify():
    bot_files = [
        'telegram_bot/btc_bot.py',
        'telegram_bot/forex_scalper.py',
        'telegram_bot/gold_bot.py',
        'telegram_bot/india_scalper.py',
        'telegram_bot/nifty_scalper.py',
        'telegram_bot/options_scalper.py',
        'telegram_bot/scanner_bot.py',
        'telegram_bot/signal_bot.py',
    ]

    print("=" * 60)
    print("TELEGRAM-ONLY NOTIFICATION VERIFICATION")
    print("=" * 60)

    # 1. Python compilation
    print("\n[1] Python Compilation Check")
    for f in bot_files + ['telegram_bot/test_telegram_only.py']:
        try:
            py_compile.compile(f, doraise=True)
            print(f"  ✓ {f}")
        except Exception as e:
            print(f"  ✗ {f}: {e}")
            return False

    # 2. Helper modules deleted
    print("\n[2] Helper Modules Deletion Check")
    if os.path.exists('telegram_bot/emailer.py'):
        print("  ✗ emailer.py still exists")
        return False
    if os.path.exists('telegram_bot/whatsapp.py'):
        print("  ✗ whatsapp.py still exists")
        return False
    print("  ✓ emailer.py deleted")
    print("  ✓ whatsapp.py deleted")

    # 3. No email/WhatsApp imports
    print("\n[3] Email/WhatsApp Removal Check")
    bad_patterns = ['import smtplib', 'from email.mime', 'graph.facebook.com']
    for bot_file in bot_files:
        with open(bot_file) as f:
            content = f.read()
        for pattern in bad_patterns:
            if pattern in content:
                print(f"  ✗ {bot_file}: found '{pattern}'")
                return False
        print(f"  ✓ {bot_file}")

    # 4. No hardcoded credentials
    print("\n[4] Hardcoded Credentials Check")
    secret_patterns = ['Bearer EAAL', 'vstbuutmlhbxbpww']
    for bot_file in bot_files:
        with open(bot_file) as f:
            content = f.read()
        for pattern in secret_patterns:
            if pattern in content:
                print(f"  ✗ {bot_file}: found '{pattern}'")
                return False
        print(f"  ✓ {bot_file}")

    # 5. No legacy Telegram variable names
    print("\n[5] Variable Standardization Check")
    legacy_names = ['BTC_BOT_TOKEN', 'ELITE_BOT_TOKEN', 'STOCX_BOT_TOKEN', 'SIGNAL_CHAT_ID', 'VANTAGE_EA_TOKEN']
    for bot_file in bot_files:
        with open(bot_file) as f:
            content = f.read()
        for legacy in legacy_names:
            if legacy in content:
                print(f"  ✗ {bot_file}: found legacy '{legacy}'")
                return False
        print(f"  ✓ {bot_file}")

    # 6. All bots use standard variables
    print("\n[6] Standard Variable Usage Check")
    for bot_file in bot_files:
        with open(bot_file) as f:
            content = f.read()
        if 'TELEGRAM_BOT_TOKEN' not in content:
            print(f"  ✗ {bot_file}: does not use TELEGRAM_BOT_TOKEN")
            return False
        if 'TELEGRAM_CHAT_ID' not in content:
            print(f"  ✗ {bot_file}: does not use TELEGRAM_CHAT_ID")
            return False
        print(f"  ✓ {bot_file}")

    print("\n" + "=" * 60)
    print("✓ ALL VERIFICATIONS PASSED")
    print("=" * 60)
    return True

if __name__ == "__main__":
    sys.exit(0 if verify() else 1)
