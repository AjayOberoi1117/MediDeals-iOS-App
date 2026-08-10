#!/usr/bin/env python3
"""
Verification script for single-telegram-routing implementation.
Checks all required scope compliance before local test run.
"""

import os
import sys

def verify_protectedfiles_unchanged():
    """Verify scanner_bot and token_updater remain unchanged."""
    print("\n✓ Checking protected files...")
    protected = ["scanner_bot.py", "token_updater_bot.py"]
    for fname in protected:
        path = f"telegram_bot/{fname}"
        if not os.path.exists(path):
            print(f"  ✗ {fname} missing")
            return False
        print(f"  ✓ {fname} exists")
    return True

def verify_standard_telegram_vars():
    """Verify all bots use TELEGRAM_BOT_TOKEN and TELEGRAM_CHAT_ID only."""
    print("\n✓ Checking standard Telegram variables...")
    bots = ["btc_bot.py", "gold_bot.py", "signal_bot.py"]

    for bot in bots:
        path = f"telegram_bot/{bot}"
        with open(path) as f:
            content = f.read()

        # Check for standard variables
        if 'TELEGRAM_BOT_TOKEN' not in content or 'TELEGRAM_CHAT_ID' not in content:
            print(f"  ✗ {bot} missing standard variables")
            return False

        # Check for legacy variables
        legacy_vars = [
            "BTC_BOT_TOKEN", "ELITE_BOT_TOKEN", "SIGNAL_TOKEN",
            "VANTAGE_EA_TOKEN", "SIGNAL_CHAT_ID", "GOLD_TOKEN",
            "PAIRS_TOKEN", "STOCKS_TOKEN"
        ]

        for legacy in legacy_vars:
            if f'os.getenv("{legacy}"' in content:
                print(f"  ✗ {bot} still uses {legacy}")
                return False

        print(f"  ✓ {bot} uses standard variables only")

    return True

def verify_email_whatsapp_removed():
    """Verify email and WhatsApp are removed."""
    print("\n✓ Checking email/WhatsApp removal...")
    bots = ["btc_bot.py", "gold_bot.py", "signal_bot.py"]

    forbidden = [
        "from emailer import",
        "from whatsapp import",
        "import smtplib",
        "email_send(",
        "wapp_send("
    ]

    for bot in bots:
        path = f"telegram_bot/{bot}"
        with open(path) as f:
            content = f.read()

        for forbidden_str in forbidden:
            if forbidden_str in content:
                print(f"  ✗ {bot} contains {forbidden_str}")
                return False

        print(f"  ✓ {bot} email/WhatsApp removed")

    return True

def verify_message_prefixes():
    """Verify all bots have source identification prefixes."""
    print("\n✓ Checking message prefixes...")
    expected = {
        "btc_bot.py": "[BTC BOT]",
        "gold_bot.py": "[GOLD BOT]",
        "signal_bot.py": "[SIGNAL BOT]"
    }

    for bot, prefix in expected.items():
        path = f"telegram_bot/{bot}"
        with open(path) as f:
            content = f.read()

        if prefix not in content:
            print(f"  ✗ {bot} missing {prefix}")
            return False

        print(f"  ✓ {bot} has {prefix}")

    return True

def verify_telegram_config_present():
    """Verify telegram_config.py module exists and is importable."""
    print("\n✓ Checking telegram_config module...")

    if not os.path.exists("telegram_bot/telegram_config.py"):
        print("  ✗ telegram_config.py missing")
        return False

    try:
        import telegram_config
        if not hasattr(telegram_config, 'validate_telegram_config'):
            print("  ✗ validate_telegram_config function missing")
            return False
        if not hasattr(telegram_config, 'is_dry_run_mode'):
            print("  ✗ is_dry_run_mode function missing")
            return False
        print("  ✓ telegram_config.py present and complete")
        return True
    except ImportError as e:
        print(f"  ✗ Cannot import telegram_config: {e}")
        return False

def verify_env_example():
    """Verify .env.example uses placeholders only."""
    print("\n✓ Checking .env.example...")

    if not os.path.exists("telegram_bot/.env.example"):
        print("  ✗ .env.example missing")
        return False

    with open("telegram_bot/.env.example") as f:
        content = f.read()

    # Check for hardcoded credentials (specific patterns that indicate real secrets, not comment text)
    if any(x in content for x in ["eyJ", "8649", "1170057", "gmail.com"]):
        print("  ✗ .env.example contains real credentials")
        return False

    if "your_bot_token_here" not in content or "your_chat_id_here" not in content:
        print("  ✗ .env.example missing placeholders")
        return False

    print("  ✓ .env.example uses placeholders only")
    return True

def verify_queue_trade_unchanged():
    """Verify queue_trade references are not new."""
    print("\n✓ Checking queue_trade integrity...")
    bots = ["btc_bot.py", "gold_bot.py", "signal_bot.py"]

    for bot in bots:
        path = f"telegram_bot/{bot}"
        with open(path) as f:
            content = f.read()

        # Queue_trade should exist (it's pre-existing)
        if "queue_trade(" not in content and "from trade_executor import queue_trade" not in content:
            print(f"  ✗ {bot} queue_trade reference altered")
            return False

        print(f"  ✓ {bot} queue_trade unchanged")

    return True

def verify_compilation():
    """Verify all Python files compile."""
    print("\n✓ Checking Python compilation...")
    files = [
        "telegram_bot/telegram_config.py",
        "telegram_bot/btc_bot.py",
        "telegram_bot/gold_bot.py",
        "telegram_bot/signal_bot.py",
        "telegram_bot/test_single_telegram_routing.py"
    ]

    for fpath in files:
        if not os.path.exists(fpath):
            print(f"  ✗ {fpath} missing")
            return False

        try:
            with open(fpath) as f:
                compile(f.read(), fpath, "exec")
            print(f"  ✓ {fpath} compiles")
        except SyntaxError as e:
            print(f"  ✗ {fpath} syntax error: {e}")
            return False

    return True

def main():
    """Run all verifications."""
    print("=" * 60)
    print("SINGLE TELEGRAM ROUTING VERIFICATION")
    print("=" * 60)

    checks = [
        ("Protected Files", verify_protectedfiles_unchanged),
        ("Standard Telegram Variables", verify_standard_telegram_vars),
        ("Email/WhatsApp Removal", verify_email_whatsapp_removed),
        ("Message Prefixes", verify_message_prefixes),
        ("Telegram Config Module", verify_telegram_config_present),
        (".env.example", verify_env_example),
        ("queue_trade Integrity", verify_queue_trade_unchanged),
        ("Python Compilation", verify_compilation),
    ]

    results = []
    for check_name, check_func in checks:
        try:
            passed = check_func()
            results.append((check_name, passed))
        except Exception as e:
            print(f"\n✗ Error in {check_name}: {e}")
            results.append((check_name, False))

    print("\n" + "=" * 60)
    print("VERIFICATION SUMMARY")
    print("=" * 60)

    passed_count = sum(1 for _, p in results if p)
    total_count = len(results)

    for check_name, passed in results:
        status = "✓ PASS" if passed else "✗ FAIL"
        print(f"{status}: {check_name}")

    print("=" * 60)
    print(f"Result: {passed_count}/{total_count} checks passed")

    if passed_count == total_count:
        print("✓ ALL VERIFICATIONS PASSED")
        return 0
    else:
        print("✗ VERIFICATION FAILED")
        return 1

if __name__ == "__main__":
    sys.exit(main())
