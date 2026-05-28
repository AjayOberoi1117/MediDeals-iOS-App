//+------------------------------------------------------------------+
//| TelegramForexBot.mq5                                             |
//| Paste this into MetaEditor (MT5), compile, and attach to a chart.|
//|                                                                  |
//| Before running:                                                  |
//|   MT5 → Tools → Options → Expert Advisors                       |
//|   ✓ Allow WebRequest for listed URL:                             |
//|     https://api.telegram.org                                     |
//|                                                                  |
//| Commands your Telegram users can send:                           |
//|   /rate EURUSD   — live mid price                                |
//|   /info EURUSD   — bid, ask, spread, daily high/low              |
//|   /pairs         — list of common symbols                        |
//|   /help          — command list                                  |
//+------------------------------------------------------------------+
#property copyright "Vantage Telegram Forex Bot"
#property version   "1.10"
#property strict

//──────────────────────────────────────────────────────────────────
// INPUT PARAMETERS — fill these in MetaEditor before compiling
//──────────────────────────────────────────────────────────────────
input string InpBotToken    = "8708193257:AAG6wpyb8popoOmDxnmjP15OaTc2R0sf9Nc"; // Elite bot token
// To use Stocx bot instead, replace with:
// "8649245457:AAFpe95Us_eiVTuewD1f7TJG2gRwUMX0zuA"

input int    InpPollSeconds = 3;   // How often to check for new messages (seconds)
input bool   InpLogRequests = true; // Print raw API responses to Experts log

//──────────────────────────────────────────────────────────────────
// GLOBALS
//──────────────────────────────────────────────────────────────────
string BASE_URL;
long   g_lastUpdateId = 0;

string PAIRS_LIST =
    "EURUSD  GBPUSD  USDJPY  USDCHF  AUDUSD\n"
    "USDCAD  NZDUSD  EURGBP  EURJPY  GBPJPY\n"
    "XAUUSD  XAGUSD  US30    US500   BTCUSD";

//──────────────────────────────────────────────────────────────────
// INIT / DEINIT
//──────────────────────────────────────────────────────────────────
int OnInit()
{
    BASE_URL = "https://api.telegram.org/bot" + InpBotToken;
    EventSetTimer(InpPollSeconds);
    Print("TelegramForexBot started. Polling every ", InpPollSeconds, "s.");
    return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
    EventKillTimer();
    Print("TelegramForexBot stopped.");
}

void OnTick() {} // required but unused

//──────────────────────────────────────────────────────────────────
// MAIN POLL LOOP
//──────────────────────────────────────────────────────────────────
void OnTimer()
{
    string url     = BASE_URL + "/getUpdates?offset=" + IntegerToString(g_lastUpdateId + 1) + "&timeout=0";
    string response = HttpGet(url);
    if(response == "") return;

    if(InpLogRequests) Print("getUpdates: ", response);

    // Walk through all update objects in the array
    int pos = 0;
    while(true)
    {
        // Find next update_id
        int idPos = StringFind(response, "\"update_id\":", pos);
        if(idPos < 0) break;

        long updateId = (long)ExtractLong(response, idPos + 12);
        if(updateId > g_lastUpdateId) g_lastUpdateId = updateId;

        // Extract chat id
        int chatPos = StringFind(response, "\"chat\":{", idPos);
        if(chatPos < 0) break;
        int chatIdPos = StringFind(response, "\"id\":", chatPos);
        long chatId = ExtractLong(response, chatIdPos + 5);

        // Extract message text
        int textPos = StringFind(response, "\"text\":\"", idPos);
        string text = "";
        if(textPos >= 0)
        {
            text = ExtractString(response, textPos + 8);
            // Strip @BotName suffix if present
            int atSign = StringFind(text, "@");
            if(atSign >= 0) text = StringSubstr(text, 0, atSign);
            StringTrimLeft(text);
            StringTrimRight(text);
        }

        if(StringLen(text) > 0)
            HandleCommand(chatId, text);

        pos = StringFind(response, "\"update_id\":", idPos + 12);
        if(pos < 0) break;
    }
}

//──────────────────────────────────────────────────────────────────
// COMMAND DISPATCHER
//──────────────────────────────────────────────────────────────────
void HandleCommand(long chatId, string text)
{
    Print("Received from ", chatId, ": ", text);

    // Normalise to lowercase for comparison
    string cmd = text;
    StringToLower(cmd);

    if(StringFind(cmd, "/start") == 0 || StringFind(cmd, "/help") == 0)
    {
        SendMessage(chatId,
            "📈 *Vantage Forex Bot*\n\n"
            "Commands:\n"
            "  /rate EURUSD — mid price\n"
            "  /info EURUSD — bid/ask/spread/high/low\n"
            "  /pairs       — common symbols\n"
            "  /help        — this message");
    }
    else if(StringFind(cmd, "/pairs") == 0)
    {
        SendMessage(chatId, "*Common pairs:*\n`" + PAIRS_LIST + "`\nUse /rate SYMBOL or /info SYMBOL");
    }
    else if(StringFind(cmd, "/rate ") == 0)
    {
        string sym = ExtractArg(text, 6);
        if(sym == "") { SendMessage(chatId, "Usage: /rate EURUSD"); return; }
        CmdRate(chatId, sym);
    }
    else if(StringFind(cmd, "/info ") == 0)
    {
        string sym = ExtractArg(text, 6);
        if(sym == "") { SendMessage(chatId, "Usage: /info EURUSD"); return; }
        CmdInfo(chatId, sym);
    }
    else
    {
        SendMessage(chatId, "Unknown command. Try /help");
    }
}

//──────────────────────────────────────────────────────────────────
// /rate SYMBOL
//──────────────────────────────────────────────────────────────────
void CmdRate(long chatId, string sym)
{
    sym = StringUppercase(sym);
    MqlTick tick;
    if(!SymbolInfoTick(sym, tick))
    {
        SendMessage(chatId, "❌ Symbol `" + sym + "` not found or not subscribed in MT5.");
        return;
    }
    double mid = NormalizeDouble((tick.bid + tick.ask) / 2.0, (int)SymbolInfoInteger(sym, SYMBOL_DIGITS));
    SendMessage(chatId,
        "*" + sym + "*\n"
        "  Price : `" + DoubleToString(mid, (int)SymbolInfoInteger(sym, SYMBOL_DIGITS)) + "`\n"
        "  Source: Vantage MT5 (live)");
}

//──────────────────────────────────────────────────────────────────
// /info SYMBOL
//──────────────────────────────────────────────────────────────────
void CmdInfo(long chatId, string sym)
{
    sym = StringUppercase(sym);
    MqlTick tick;
    if(!SymbolInfoTick(sym, tick))
    {
        SendMessage(chatId, "❌ Symbol `" + sym + "` not found or not subscribed in MT5.");
        return;
    }
    int    digits = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
    double point  = SymbolInfoDouble(sym, SYMBOL_POINT);
    double spread = (point > 0) ? NormalizeDouble((tick.ask - tick.bid) / point, 1) : 0;
    double high   = SymbolInfoDouble(sym, SYMBOL_SESSION_HIGH);
    double low    = SymbolInfoDouble(sym, SYMBOL_SESSION_LOW);

    string highStr = (high > 0) ? DoubleToString(high, digits) : "n/a";
    string lowStr  = (low  > 0) ? DoubleToString(low,  digits) : "n/a";

    SendMessage(chatId,
        "*" + sym + "* — Full Quote\n"
        "  Bid    : `" + DoubleToString(tick.bid, digits) + "`\n"
        "  Ask    : `" + DoubleToString(tick.ask, digits) + "`\n"
        "  Spread : `" + DoubleToString(spread, 1) + " pts`\n"
        "  High   : `" + highStr + "`\n"
        "  Low    : `" + lowStr  + "`\n"
        "  Source : Vantage MT5 (live)");
}

//──────────────────────────────────────────────────────────────────
// HTTP HELPERS
//──────────────────────────────────────────────────────────────────
string HttpGet(string url)
{
    char   req[], res[];
    string headers;
    int    timeout = 5000;
    int    code = WebRequest("GET", url, "", "", timeout, req, 0, res, headers);
    if(code != 200) { Print("WebRequest failed, code=", code, " url=", url); return ""; }
    return CharArrayToString(res, 0, WHOLE_ARRAY, CP_UTF8);
}

void SendMessage(long chatId, string text)
{
    // Encode the text into a JSON body
    string body = "{\"chat_id\":" + IntegerToString(chatId) +
                  ",\"text\":\"" + EscapeJson(text) + "\",\"parse_mode\":\"Markdown\"}";
    char   reqArr[], resArr[];
    StringToCharArray(body, reqArr, 0, StringLen(body), CP_UTF8);

    string headers = "Content-Type: application/json\r\n";
    string resHeaders;
    int code = WebRequest("POST",
                          BASE_URL + "/sendMessage",
                          headers, "", 5000,
                          reqArr, ArraySize(reqArr) - 1,
                          resArr, resHeaders);
    if(code != 200)
        Print("sendMessage failed, code=", code, " body=", body);
    else if(InpLogRequests)
        Print("sendMessage OK → chat ", chatId);
}

//──────────────────────────────────────────────────────────────────
// STRING UTILITIES
//──────────────────────────────────────────────────────────────────

// Extract a quoted JSON string value starting after pos (points past opening ")
string ExtractString(string &s, int startPos)
{
    string result = "";
    int len = StringLen(s);
    for(int i = startPos; i < len; i++)
    {
        ushort c = StringGetCharacter(s, i);
        if(c == '"') break;
        if(c == '\\') { i++; continue; } // skip escaped chars
        result += ShortToString(c);
    }
    return result;
}

// Extract a JSON integer/long starting at pos
long ExtractLong(string &s, int startPos)
{
    string num = "";
    int len = StringLen(s);
    for(int i = startPos; i < len; i++)
    {
        ushort c = StringGetCharacter(s, i);
        if(c >= '0' && c <= '9') num += ShortToString(c);
        else if(c == '-' && i == startPos) num += "-";
        else break;
    }
    return StringToInteger(num);
}

// Get the argument after a command prefix (e.g. "/rate EURUSD" → "EURUSD")
string ExtractArg(string text, int prefixLen)
{
    if(StringLen(text) <= prefixLen) return "";
    string arg = StringSubstr(text, prefixLen);
    StringTrimLeft(arg);
    StringTrimRight(arg);
    // Take first word only
    int space = StringFind(arg, " ");
    if(space >= 0) arg = StringSubstr(arg, 0, space);
    return arg;
}

// Escape special JSON characters
string EscapeJson(string s)
{
    string r = "";
    int len = StringLen(s);
    for(int i = 0; i < len; i++)
    {
        ushort c = StringGetCharacter(s, i);
        if     (c == '"')  r += "\\\"";
        else if(c == '\\') r += "\\\\";
        else if(c == '\n') r += "\\n";
        else if(c == '\r') r += "\\r";
        else               r += ShortToString(c);
    }
    return r;
}

// Convert string to UPPERCASE
string StringUppercase(string s)
{
    string r = s;
    StringToUpper(r);
    return r;
}
//+------------------------------------------------------------------+
