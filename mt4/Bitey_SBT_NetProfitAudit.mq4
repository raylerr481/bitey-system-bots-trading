//+------------------------------------------------------------------+
//| Bitey_SBT_NetProfitAudit.mq4                                     |
//| Read-only audit: realized P/L net of commission and swap.         |
//| Writes CSV files to MT4 Terminal\Common\Files.                  |
//+------------------------------------------------------------------+
#property strict
#property script_show_inputs

input int    InpBiteyMagicNumber = 21102027;
input string InpCommentMarker    = "21102027";
input bool   InpMatchMagicOrComment = true;

string SafeCsv(string value)
{
   StringReplace(value, ";", "_");
   StringReplace(value, "\r", " ");
   StringReplace(value, "\n", " ");
   return value;
}

bool IsBiteyOrder()
{
   bool magicMatch = (OrderMagicNumber() == InpBiteyMagicNumber);
   bool commentMatch = (StringFind(OrderComment(), InpCommentMarker, 0) >= 0);
   if(InpMatchMagicOrComment)
      return (magicMatch || commentMatch);
   return magicMatch;
}

int FindSymbol(string symbol, string &symbols[], int count)
{
   for(int i=0; i<count; i++)
      if(symbols[i] == symbol) return i;
   return -1;
}

void OnStart()
{
   int total = OrdersHistoryTotal();
   string detailName = "Bitey_SBT_TradeNetAudit.csv";
   string summaryName = "Bitey_SBT_AssetNetSummary.csv";

   int detail = FileOpen(detailName, FILE_WRITE|FILE_CSV|FILE_COMMON, ';');
   if(detail == INVALID_HANDLE)
   {
      Print("Bitey Net Audit: cannot open ", detailName, " error=", GetLastError());
      return;
   }

   FileWrite(detail, "ticket","symbol","side","lots","open_time","close_time",
             "open_price","close_price","gross_profit","commission","swap","net_profit",
             "magic_number","comment");

   string symbols[512];
   int counts[512], wins[512], losses[512];
   double gross[512], commissions[512], swaps[512], nets[512];
   ArrayInitialize(counts,0);
   ArrayInitialize(wins,0);
   ArrayInitialize(losses,0);
   ArrayInitialize(gross,0.0);
   ArrayInitialize(commissions,0.0);
   ArrayInitialize(swaps,0.0);
   ArrayInitialize(nets,0.0);
   int symbolCount=0, included=0;
   double allGross=0.0, allCommission=0.0, allSwap=0.0, allNet=0.0;
   int allWins=0, allLosses=0;

   for(int pos=0; pos<total; pos++)
   {
      if(!OrderSelect(pos, SELECT_BY_POS, MODE_HISTORY)) continue;
      if(!IsBiteyOrder()) continue;
      int type=OrderType();
      if(type!=OP_BUY && type!=OP_SELL) continue;

      double g=OrderProfit();
      double c=OrderCommission();
      double s=OrderSwap();
      double n=g+c+s;
      string side=(type==OP_BUY ? "BUY" : "SELL");
      string comment=SafeCsv(OrderComment());

      FileWrite(detail,
         OrderTicket(), OrderSymbol(), side, DoubleToString(OrderLots(),2),
         TimeToString(OrderOpenTime(),TIME_DATE|TIME_SECONDS),
         TimeToString(OrderCloseTime(),TIME_DATE|TIME_SECONDS),
         DoubleToString(OrderOpenPrice(),Digits),
         DoubleToString(OrderClosePrice(),Digits),
         DoubleToString(g,2), DoubleToString(c,2), DoubleToString(s,2),
         DoubleToString(n,2), OrderMagicNumber(), comment);

      int idx=FindSymbol(OrderSymbol(),symbols,symbolCount);
      if(idx<0 && symbolCount<512)
      {
         idx=symbolCount++;
         symbols[idx]=OrderSymbol();
      }
      if(idx>=0)
      {
         counts[idx]++;
         gross[idx]+=g;
         commissions[idx]+=c;
         swaps[idx]+=s;
         nets[idx]+=n;
         if(n>0.000001) wins[idx]++;
         else if(n< -0.000001) losses[idx]++;
      }
      included++;
      allGross+=g;
      allCommission+=c;
      allSwap+=s;
      allNet+=n;
      if(n>0.000001) allWins++;
      else if(n< -0.000001) allLosses++;
   }
   FileClose(detail);

   int summary=FileOpen(summaryName, FILE_WRITE|FILE_CSV|FILE_COMMON, ';');
   if(summary==INVALID_HANDLE)
   {
      Print("Bitey Net Audit: details exported, but cannot open ", summaryName,
            " error=",GetLastError());
      return;
   }
   FileWrite(summary,"symbol","trades","wins_net","losses_net","gross_profit",
             "commission","swap","net_profit");
   for(int j=0;j<symbolCount;j++)
      FileWrite(summary,symbols[j],counts[j],wins[j],losses[j],
                DoubleToString(gross[j],2),DoubleToString(commissions[j],2),
                DoubleToString(swaps[j],2),DoubleToString(nets[j],2));
   FileWrite(summary,"TOTAL",included,allWins,allLosses,
             DoubleToString(allGross,2),DoubleToString(allCommission,2),
             DoubleToString(allSwap,2),DoubleToString(allNet,2));
   FileClose(summary);

   Print("Bitey Net Audit complete. Closed Bitey trades=",included,
         " net=",DoubleToString(allNet,2),
         " commission=",DoubleToString(allCommission,2),
         " swap=",DoubleToString(allSwap,2),
         ". Files in Terminal Common Files: ",detailName," and ",summaryName,
         ". Ensure MT4 Account History is set to All History for complete results.");
}
