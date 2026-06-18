//+------------------------------------------------------------------+
//| TradeFromFile.mq5                                                |
//| Reads mt5_signals.csv written by trader.py (Linux) and          |
//| executes trades. Magic numbers identify each bot+timeframe.      |
//|                                                                  |
//| Deploy: copy to MQL5\Experts\, compile, attach to any chart.    |
//+------------------------------------------------------------------+
#property copyright "MediDeals Trading Bots"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>

CTrade trade;

input double LotSize      = 0.01;   // Lot size per trade
input int    Deviation    = 20;     // Max slippage in points
input int    CheckSecs    = 5;      // How often to check for signals (seconds)
input string SignalsFile  = "mt5_signals.csv"; // File written by trader.py

int OnInit()
{
   trade.SetDeviationInPoints(Deviation);
   EventSetTimer(CheckSecs);
   Print("TradeFromFile EA started | watching: ", SignalsFile, " every ", CheckSecs, "s");
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   EventKillTimer();
}

void OnTimer()
{
   ProcessSignals();
}

void ProcessSignals()
{
   if (!FileIsExist(SignalsFile))
      return;

   int handle = FileOpen(SignalsFile, FILE_READ|FILE_TXT|FILE_ANSI);
   if (handle == INVALID_HANDLE)
      return;

   string lines[];
   int count = 0;
   while (!FileIsEnding(handle))
   {
      string line = StringTrimRight(StringTrimLeft(FileReadString(handle)));
      if (StringLen(line) > 5)
      {
         ArrayResize(lines, count + 1);
         lines[count++] = line;
      }
   }
   FileClose(handle);

   if (count == 0) return;

   // Clear file immediately so we don't re-process
   handle = FileOpen(SignalsFile, FILE_WRITE|FILE_TXT|FILE_ANSI);
   if (handle != INVALID_HANDLE) FileClose(handle);

   for (int i = 0; i < count; i++)
   {
      string parts[];
      // Format: SYMBOL,DIRECTION,SL,TP,MAGIC,SOURCE,TIMESTAMP
      if (StringSplit(lines[i], ',', parts) < 5) continue;

      string symbol    = parts[0];
      string direction = parts[1];
      double sl        = StringToDouble(parts[2]);
      double tp        = StringToDouble(parts[3]);
      int    magic     = (int)StringToInteger(parts[4]);

      // Skip signals older than 5 minutes
      if (ArraySize(parts) >= 7)
      {
         double ts = StringToDouble(parts[6]);
         if (ts > 0 && (TimeCurrent() - (datetime)ts) > 300)
         {
            Print("SKIP stale signal: ", direction, " ", symbol, " age=",
                  (int)(TimeCurrent() - (datetime)ts), "s");
            continue;
         }
      }

      ExecuteTrade(symbol, direction, sl, tp, magic);
   }
}

void ExecuteTrade(string symbol, string direction, double sl, double tp, int magic)
{
   trade.SetExpertMagicNumber(magic);

   bool ok = false;
   string comment = "Bot#" + IntegerToString(magic);

   if (direction == "BUY")
      ok = trade.Buy(LotSize, symbol, 0, sl, tp, comment);
   else if (direction == "SELL")
      ok = trade.Sell(LotSize, symbol, 0, sl, tp, comment);
   else
   {
      Print("Unknown direction: ", direction);
      return;
   }

   if (ok)
      Print("TRADE OK: ", direction, " ", symbol,
            " lot=", LotSize, " sl=", sl, " tp=", tp, " magic=", magic);
   else
      Print("TRADE FAILED: ", direction, " ", symbol,
            " error=", GetLastError(), " magic=", magic);
}
