//+------------------------------------------------------------------+
//| Turtle v1.26 SBT integration helper                              |
//| Read-only telemetry. No trading commands.                       |
//+------------------------------------------------------------------+
#property strict

string TurtleSbtRegime()
{
   if(g_campaign.active)
      return StringFormat("CAMPAIGN_%s_%s_U%d",
                          DirectionName(g_campaign.direction),
                          SystemName(g_campaign.system),
                          g_campaign.units);

   bool s1b=S1SignalExists(1);
   bool s1s=S1SignalExists(-1);
   bool s2b=S2SignalExists(1);
   bool s2s=S2SignalExists(-1);

   if(s1b || s2b) return "BREAKOUT_LONG";
   if(s1s || s2s) return "BREAKOUT_SHORT";
   return "FLAT";
}

void SendTurtleSbtSnapshot()
{
   if(!InpMcpStateExport) return;

   static datetime lastSend=0;
   datetime now=TimeCurrent();
   int interval=MathMax(2,InpMcpExportSeconds);
   if(lastSend>0 && (now-lastSend)<interval) return;
   lastSend=now;

   RefreshRates();

   double atr=iATR(Symbol(),InpTimeframe,InpNPeriod,1);
   double rsi=iRSI(Symbol(),InpTimeframe,14,PRICE_CLOSE,1);
   double adx=iADX(Symbol(),InpTimeframe,14,PRICE_CLOSE,MODE_MAIN,1);

   int dir=g_campaign.active ? g_campaign.direction : 0;
   string htfDirection="FLAT";
   if(dir>0) htfDirection="BUY";
   else if(dir<0) htfDirection="SELL";

   double scoreGap=0.0;
   string strategy="TURTLE_CLASSIC";

   bool ok=BiteySendTurtleSnapshot(
      Symbol(),
      TfName(),
      IsTester() ? "tester" : "live_read_only",
      TurtleSbtRegime(),
      EMPTY_VALUE,
      strategy,
      1.0,
      scoreGap,
      htfDirection,
      Bid,
      Ask,
      atr,
      rsi,
      adx,
      AccountBalance(),
      AccountEquity(),
      OpenOrderCount(),
      g_campaign.id,
      g_campaign.system,
      g_campaign.direction,
      g_campaign.units,
      g_campaign.lastEntry,
      g_campaign.n,
      g_campaign.active,
      g_skipS1Next,
      g_s1SkipLatched
   );

   if(ok && InpVerbose)
      Print("Bitey SBT Turtle snapshot sent. regime=",TurtleSbtRegime(),
            " campaign=",g_campaign.id,
            " units=",g_campaign.units);
}
