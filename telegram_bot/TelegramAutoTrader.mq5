//+------------------------------------------------------------------+
//| TelegramAutoTrader.mq5                                           |
//| Fully automated EA -- EMA crossover + RSI filter                 |
//| Sends all trade events and daily P&L to Telegram                 |
//|                                                                  |
//| SETUP (do this before attaching to chart):                       |
//|  1. MT5 -> Tools -> Options -> Expert Advisors                   |
//|     Allow WebRequest for listed URL:                             |
//|       https://api.telegram.org                                   |
//|  2. Attach EA to EURUSD H1 chart ONLY                            |
//|  3. Click "Allow algo trading" in the toolbar (smiley face icon) |
//|  4. Open Telegram, send /start to @VantageEA_bot                 |
//|                                                                  |
//| Telegram commands:                                               |
//|  /status  -- open positions + floating P&L + equity              |
//|  /pnl     -- today's closed trade summary                        |
//|  /pause   -- stop opening new trades (keeps existing open)       |
//|  /resume  -- resume auto-trading                                 |
//|  /close   -- close ALL open trades immediately                   |
//|  /help    -- show command list                                   |
//+------------------------------------------------------------------+
#property copyright "Vantage Auto Trader"
#property version   "2.01"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

//------------------------------------------------------------------
// INPUTS
//------------------------------------------------------------------

// --- Telegram ---
input string           InpBotToken     = "8034731398:AAHHAKJaYEn_u0M_TzwSJr8e7tNtQIwN5BM"; // VantageEA_bot token
input long             InpChatId       = 1994067941;  // Your Telegram chat ID
input int              InpPollSeconds  = 3;            // How often to check Telegram (seconds)

// --- Symbols ---
input string           InpSymbols      = "EURUSD,GBPUSD,USDJPY,XAUUSD";

// --- Risk management ---
input double           InpLotSize      = 0.01;  // Lot size per trade
input int              InpStopPips     = 30;    // Stop loss (pips)
input int              InpTakePips     = 60;    // Take profit (pips, 0 = none)
input int              InpMaxTrades    = 4;     // Max concurrent open trades
input bool             InpTrailingStop = true;  // Enable trailing stop
input int              InpTrailPips    = 20;    // Trailing stop distance (pips)

// --- Signal ---
input ENUM_TIMEFRAMES  InpTF           = PERIOD_H1;  // Timeframe for signals
input int              InpFastMA       = 10;    // Fast EMA period
input int              InpSlowMA       = 50;    // Slow EMA period
input int              InpRSIPeriod    = 14;    // RSI period
input int              InpRSIBuyMax    = 65;    // Max RSI to open a BUY (avoids overbought)
input int              InpRSISellMin   = 35;    // Min RSI to open a SELL (avoids oversold)

// --- Schedule ---
input int              InpSummaryHour  = 20;    // Daily P&L summary hour (server time 0-23)

//------------------------------------------------------------------
// GLOBALS
//------------------------------------------------------------------
CTrade        g_trade;
CPositionInfo g_pos;

string   g_baseUrl;
long     g_lastUpdateId = 0;
long     g_chatId       = 0;
bool     g_paused       = false;
int      g_summaryDay   = -1;
string   g_symbols[];
int      g_symCount     = 0;
const int MAGIC         = 20250528;

//------------------------------------------------------------------
// LIFECYCLE
//------------------------------------------------------------------
int OnInit()
{
    g_baseUrl = "https://api.telegram.org/bot" + InpBotToken;
    g_chatId  = InpChatId;

    g_trade.SetExpertMagicNumber(MAGIC);
    g_trade.SetDeviationInPoints(10);

    g_symCount = StringSplit(InpSymbols, ',', g_symbols);
    for(int i = 0; i < g_symCount; i++)
    {
        StringTrimLeft(g_symbols[i]);
        StringTrimRight(g_symbols[i]);
        StringToUpper(g_symbols[i]);
        SymbolSelect(g_symbols[i], true);
    }

    EventSetTimer(InpPollSeconds);

    string symLine = "";
    for(int i = 0; i < g_symCount; i++)
        symLine += (i > 0 ? ", " : "") + g_symbols[i];

    TgBroadcast(
        "*Vantage Auto Trader v2.01 -- Online*\n\n"
        "Symbols : " + symLine + "\n"
        "Lot     : " + DoubleToString(InpLotSize, 2) + "\n"
        "SL / TP : " + IntegerToString(InpStopPips) + " / " + IntegerToString(InpTakePips) + " pips\n"
        "Trailing: " + (InpTrailingStop ? IntegerToString(InpTrailPips) + " pips" : "off") + "\n"
        "TF      : " + EnumToString(InpTF) + "\n"
        "Max open: " + IntegerToString(InpMaxTrades) + "\n\n"
        "Send /help for commands."
    );

    return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
    EventKillTimer();
    TgBroadcast("Auto Trader STOPPED (reason: " + IntegerToString(reason) + ").");
}

void OnTick() {}

//------------------------------------------------------------------
// MAIN TIMER LOOP
//------------------------------------------------------------------
void OnTimer()
{
    PollTelegram();

    if(InpTrailingStop)
        ManageTrailingStops();

    if(!g_paused && CountBotTrades() < InpMaxTrades)
    {
        for(int i = 0; i < g_symCount; i++)
            CheckSignal(g_symbols[i]);
    }

    MaybeSendDailySummary();
}

//------------------------------------------------------------------
// TRADE CLOSE NOTIFICATIONS
//------------------------------------------------------------------
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest     &req,
                        const MqlTradeResult      &res)
{
    if(trans.type != TRADE_TRANSACTION_DEAL_ADD) return;

    ulong dealTicket = trans.deal;
    if(!HistoryDealSelect(dealTicket)) return;

    if((ENUM_DEAL_ENTRY)HistoryDealGetInteger(dealTicket, DEAL_ENTRY) != DEAL_ENTRY_OUT) return;
    if(HistoryDealGetInteger(dealTicket, DEAL_MAGIC) != MAGIC) return;

    string sym    = HistoryDealGetString(dealTicket, DEAL_SYMBOL);
    double profit = HistoryDealGetDouble(dealTicket, DEAL_PROFIT)
                  + HistoryDealGetDouble(dealTicket, DEAL_SWAP)
                  + HistoryDealGetDouble(dealTicket, DEAL_COMMISSION);
    double price  = HistoryDealGetDouble(dealTicket, DEAL_PRICE);
    int    digits = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);

    string result = (profit >= 0) ? "[WIN]" : "[LOSS]";
    string sign   = (profit >= 0) ? "+" : "";
    TgBroadcast(result + " " + sym + " CLOSED\n"
                "  Exit  : " + DoubleToString(price, digits) + "\n"
                "  P&L   : " + sign + DoubleToString(profit, 2) + " USD\n"
                "  Balance: $" + DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2));
}

//------------------------------------------------------------------
// SIGNAL -- EMA CROSSOVER + RSI FILTER
//------------------------------------------------------------------
void CheckSignal(string sym)
{
    if(HasOpenTrade(sym)) return;

    int hFast = iMA(sym, InpTF, InpFastMA, 0, MODE_EMA, PRICE_CLOSE);
    int hSlow = iMA(sym, InpTF, InpSlowMA, 0, MODE_EMA, PRICE_CLOSE);
    int hRsi  = iRSI(sym, InpTF, InpRSIPeriod, PRICE_CLOSE);

    if(hFast == INVALID_HANDLE || hSlow == INVALID_HANDLE || hRsi == INVALID_HANDLE)
        return;

    double fast[], slow[], rsi[];
    ArraySetAsSeries(fast, true);
    ArraySetAsSeries(slow, true);
    ArraySetAsSeries(rsi,  true);

    bool ok = CopyBuffer(hFast, 0, 0, 3, fast) == 3 &&
              CopyBuffer(hSlow, 0, 0, 3, slow) == 3 &&
              CopyBuffer(hRsi,  0, 0, 2, rsi)  == 2;

    IndicatorRelease(hFast);
    IndicatorRelease(hSlow);
    IndicatorRelease(hRsi);

    if(!ok) return;

    bool bullCross = (fast[1] > slow[1]) && (fast[2] <= slow[2]);
    bool bearCross = (fast[1] < slow[1]) && (fast[2] >= slow[2]);

    if(bullCross && rsi[1] < (double)InpRSIBuyMax)
        OpenTrade(sym, ORDER_TYPE_BUY);
    else if(bearCross && rsi[1] > (double)InpRSISellMin)
        OpenTrade(sym, ORDER_TYPE_SELL);
}

//------------------------------------------------------------------
// OPEN TRADE
//------------------------------------------------------------------
void OpenTrade(string sym, ENUM_ORDER_TYPE type)
{
    MqlTick tick;
    if(!SymbolInfoTick(sym, tick)) return;

    int    digits = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
    double point  = SymbolInfoDouble(sym, SYMBOL_POINT);
    double pipVal = (digits == 3 || digits == 5) ? point * 10.0 : point;

    double price = 0.0, sl = 0.0, tp = 0.0;
    if(type == ORDER_TYPE_BUY)
    {
        price = tick.ask;
        if(InpStopPips > 0) sl = NormalizeDouble(price - InpStopPips * pipVal, digits);
        if(InpTakePips > 0) tp = NormalizeDouble(price + InpTakePips * pipVal, digits);
    }
    else
    {
        price = tick.bid;
        if(InpStopPips > 0) sl = NormalizeDouble(price + InpStopPips * pipVal, digits);
        if(InpTakePips > 0) tp = NormalizeDouble(price - InpTakePips * pipVal, digits);
    }

    bool sent = (type == ORDER_TYPE_BUY)
                ? g_trade.Buy (InpLotSize, sym, price, sl, tp, "TgAuto")
                : g_trade.Sell(InpLotSize, sym, price, sl, tp, "TgAuto");

    if(!sent)
    {
        Print("Order failed: ", sym, " err=", g_trade.ResultRetcode(), " ", g_trade.ResultRetcodeDescription());
        return;
    }

    string dir   = (type == ORDER_TYPE_BUY) ? "[BUY]" : "[SELL]";
    string slStr = (sl > 0) ? DoubleToString(sl, digits) : "none";
    string tpStr = (tp > 0) ? DoubleToString(tp, digits) : "none";
    TgBroadcast(dir + " " + sym + "\n"
                "  Entry : " + DoubleToString(price, digits) + "\n"
                "  SL    : " + slStr + "\n"
                "  TP    : " + tpStr + "\n"
                "  Lot   : " + DoubleToString(InpLotSize, 2) + "\n"
                "  Signal: EMA cross + RSI on " + EnumToString(InpTF));
}

//------------------------------------------------------------------
// TRAILING STOP
//------------------------------------------------------------------
void ManageTrailingStops()
{
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        if(!g_pos.SelectByIndex(i)) continue;
        if(g_pos.Magic() != MAGIC)  continue;

        string sym    = g_pos.Symbol();
        int    digits = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
        double point  = SymbolInfoDouble(sym, SYMBOL_POINT);
        double pipVal = (digits == 3 || digits == 5) ? point * 10.0 : point;
        double trail  = InpTrailPips * pipVal;

        MqlTick tick;
        if(!SymbolInfoTick(sym, tick)) continue;

        double newSL = 0.0;
        if(g_pos.PositionType() == POSITION_TYPE_BUY)
        {
            newSL = NormalizeDouble(tick.bid - trail, digits);
            if(newSL > g_pos.StopLoss() + point)
                g_trade.PositionModify(g_pos.Ticket(), newSL, g_pos.TakeProfit());
        }
        else
        {
            newSL = NormalizeDouble(tick.ask + trail, digits);
            if(g_pos.StopLoss() == 0 || newSL < g_pos.StopLoss() - point)
                g_trade.PositionModify(g_pos.Ticket(), newSL, g_pos.TakeProfit());
        }
    }
}

//------------------------------------------------------------------
// CLOSE ALL
//------------------------------------------------------------------
void CloseAllTrades()
{
    int n = 0;
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        if(!g_pos.SelectByIndex(i)) continue;
        if(g_pos.Magic() != MAGIC)  continue;
        if(g_trade.PositionClose(g_pos.Ticket())) n++;
    }
    TgBroadcast("Closed " + IntegerToString(n) + " trade(s).");
}

//------------------------------------------------------------------
// /status
//------------------------------------------------------------------
void SendStatus()
{
    int    n   = 0;
    double fpl = 0;
    string msg = "Open Positions:\n";

    for(int i = 0; i < PositionsTotal(); i++)
    {
        if(!g_pos.SelectByIndex(i)) continue;
        if(g_pos.Magic() != MAGIC)  continue;

        string dir    = (g_pos.PositionType() == POSITION_TYPE_BUY) ? "[BUY]" : "[SELL]";
        int    digits = (int)SymbolInfoInteger(g_pos.Symbol(), SYMBOL_DIGITS);
        string pnlStr = (g_pos.Profit() >= 0 ? "+" : "") + DoubleToString(g_pos.Profit(), 2);

        msg += dir + " " + g_pos.Symbol() + " @ " +
               DoubleToString(g_pos.PriceOpen(), digits) + "  P&L: " + pnlStr + "\n";
        fpl += g_pos.Profit();
        n++;
    }

    if(n == 0) msg = "No open positions.\n";

    double bal    = AccountInfoDouble(ACCOUNT_BALANCE);
    double eq     = AccountInfoDouble(ACCOUNT_EQUITY);
    string fplStr = (fpl >= 0 ? "+" : "") + DoubleToString(fpl, 2);

    msg += "\nFloating P&L : " + fplStr + " USD\n"
           "Balance      : $" + DoubleToString(bal, 2) + "\n"
           "Equity       : $" + DoubleToString(eq,  2) + "\n"
           "Status       : " + (g_paused ? "PAUSED" : "RUNNING");

    TgBroadcast(msg);
}

//------------------------------------------------------------------
// /pnl -- today's closed trade stats
//------------------------------------------------------------------
void SendPnLSummary()
{
    datetime dayStart = StringToTime(TimeToString(TimeCurrent(), TIME_DATE));
    HistorySelect(dayStart, TimeCurrent());

    int    wins = 0, losses = 0;
    double net  = 0;

    for(int i = 0; i < HistoryDealsTotal(); i++)
    {
        ulong t = HistoryDealGetTicket(i);
        if(HistoryDealGetInteger(t, DEAL_MAGIC) != MAGIC) continue;
        if((ENUM_DEAL_ENTRY)HistoryDealGetInteger(t, DEAL_ENTRY) != DEAL_ENTRY_OUT) continue;

        double p = HistoryDealGetDouble(t, DEAL_PROFIT)
                 + HistoryDealGetDouble(t, DEAL_SWAP)
                 + HistoryDealGetDouble(t, DEAL_COMMISSION);
        net += p;
        if(p >= 0) wins++; else losses++;
    }

    double bal  = AccountInfoDouble(ACCOUNT_BALANCE);
    string sign = (net >= 0) ? "+" : "";
    string icon = (net >= 0) ? "[UP]" : "[DOWN]";

    TgBroadcast(icon + " Daily P&L Summary\n"
                "  Trades  : " + IntegerToString(wins + losses) +
                " (W:" + IntegerToString(wins) + " L:" + IntegerToString(losses) + ")\n"
                "  Net P&L : " + sign + DoubleToString(net, 2) + " USD\n"
                "  Balance : $" + DoubleToString(bal, 2));
}

void MaybeSendDailySummary()
{
    MqlDateTime t;
    TimeToStruct(TimeCurrent(), t);
    if(t.hour == InpSummaryHour && t.day != g_summaryDay)
    {
        g_summaryDay = t.day;
        SendPnLSummary();
    }
}

//------------------------------------------------------------------
// TELEGRAM POLLING
//------------------------------------------------------------------
void PollTelegram()
{
    string url  = g_baseUrl + "/getUpdates?offset=" + IntegerToString(g_lastUpdateId + 1) + "&timeout=0";
    string resp = HttpGet(url);
    if(resp == "") return;

    int cursor = 0;
    while(true)
    {
        int p = StringFind(resp, "\"update_id\":", cursor);
        if(p < 0) break;

        long uid = ExtractLong(resp, p + 12);
        if(uid > g_lastUpdateId) g_lastUpdateId = uid;

        int cp  = StringFind(resp, "\"chat\":{", p);
        if(cp < 0) break;
        int cip = StringFind(resp, "\"id\":", cp);
        long chatId = ExtractLong(resp, cip + 5);

        if(g_chatId == 0 && chatId != 0) g_chatId = chatId;

        int tp2 = StringFind(resp, "\"text\":\"", p);
        string text = "";
        if(tp2 >= 0)
        {
            text = ExtractJsonString(resp, tp2 + 8);
            int at = StringFind(text, "@");
            if(at >= 0) text = StringSubstr(text, 0, at);
            StringTrimLeft(text);
            StringTrimRight(text);
        }

        if(StringLen(text) > 0)
            HandleTgCommand(chatId, text);

        cursor = StringFind(resp, "\"update_id\":", p + 12);
        if(cursor < 0) break;
    }
}

void HandleTgCommand(long chatId, string rawText)
{
    string cmd = rawText;
    StringToLower(cmd);

    if(StringFind(cmd, "/start") == 0 || StringFind(cmd, "/help") == 0)
    {
        g_chatId = chatId;
        TgSend(chatId,
            "Vantage Auto Trader v2.01\n\n"
            "/status -- open positions + equity\n"
            "/pnl    -- today's P&L summary\n"
            "/pause  -- stop opening new trades\n"
            "/resume -- restart auto-trading\n"
            "/close  -- close ALL open trades\n"
            "/help   -- this message\n\n"
            "Status: " + (g_paused ? "PAUSED" : "RUNNING"));
    }
    else if(StringFind(cmd, "/status") == 0)  SendStatus();
    else if(StringFind(cmd, "/pnl")    == 0)  SendPnLSummary();
    else if(StringFind(cmd, "/pause")  == 0)
    {
        g_paused = true;
        TgBroadcast("Trading PAUSED. Existing trades remain open.\nSend /resume to restart.");
    }
    else if(StringFind(cmd, "/resume") == 0)
    {
        g_paused = false;
        TgBroadcast("Trading RESUMED.");
    }
    else if(StringFind(cmd, "/close") == 0)
        CloseAllTrades();
    else
        TgSend(chatId, "Unknown command. Try /help");
}

//------------------------------------------------------------------
// TELEGRAM SEND HELPERS
//------------------------------------------------------------------
void TgSend(long chatId, string text)
{
    if(chatId == 0) return;
    string url = g_baseUrl + "/sendMessage?chat_id=" + IntegerToString(chatId)
                           + "&text=" + TgUrlEncode(text);
    string resp = HttpGet(url);
    if(StringFind(resp, "\"ok\":true") < 0)
        Print("sendMessage GET failed chatId=", chatId);
}

string TgUrlEncode(string s)
{
    string r = "";
    int len = StringLen(s);
    for(int i = 0; i < len; i++)
    {
        ushort c = StringGetCharacter(s, i);
        if     (c == ' ')  r += "+";
        else if(c == '\n') r += "%0A";
        else if(c == '\r') {}
        else if(c == '&')  r += "%26";
        else if(c == '+')  r += "%2B";
        else if(c == '%')  r += "%25";
        else if(c == '#')  r += "%23";
        else if(c == '=')  r += "%3D";
        else               r += ShortToString(c);
    }
    return r;
}

void TgBroadcast(string text)
{
    if(g_chatId != 0)
        TgSend(g_chatId, text);
    else
        Print("TgBroadcast (no chat registered): ", text);
}

//------------------------------------------------------------------
// HTTP & STRING UTILITIES
//------------------------------------------------------------------
string HttpGet(string url)
{
    char req[], res[];
    string headers;
    int code = WebRequest("GET", url, "", "", 5000, req, 0, res, headers);
    if(code != 200) { if(code > 0) Print("WebRequest GET failed code=", code); return ""; }
    return CharArrayToString(res, 0, WHOLE_ARRAY, CP_UTF8);
}

long ExtractLong(string &s, int start)
{
    string n = "";
    int len  = StringLen(s);
    for(int i = start; i < len; i++)
    {
        ushort c = StringGetCharacter(s, i);
        if(c >= '0' && c <= '9') n += ShortToString(c);
        else if(c == '-' && i == start) n += "-";
        else break;
    }
    return StringToInteger(n);
}

string ExtractJsonString(string &s, int start)
{
    string r = "";
    int len  = StringLen(s);
    for(int i = start; i < len; i++)
    {
        ushort c = StringGetCharacter(s, i);
        if(c == '"')  break;
        if(c == '\\') { i++; continue; }
        r += ShortToString(c);
    }
    return r;
}

string EscapeJson(string s)
{
    string r = "";
    int len  = StringLen(s);
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

bool HasOpenTrade(string sym)
{
    for(int i = 0; i < PositionsTotal(); i++)
    {
        if(!g_pos.SelectByIndex(i)) continue;
        if(g_pos.Symbol() == sym && g_pos.Magic() == MAGIC) return true;
    }
    return false;
}

int CountBotTrades()
{
    int n = 0;
    for(int i = 0; i < PositionsTotal(); i++)
    {
        if(g_pos.SelectByIndex(i) && g_pos.Magic() == MAGIC) n++;
    }
    return n;
}
//+------------------------------------------------------------------+
