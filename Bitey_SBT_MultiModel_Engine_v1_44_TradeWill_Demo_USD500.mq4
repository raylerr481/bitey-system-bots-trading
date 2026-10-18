#property strict
#property version   "1.44"
#property description "Bitey SBT Multi-Model Engine v1.44 - user-confirmed demo execution with real-style USD500 risk controls"

// IMPORTANT
// - The user confirms this is a Trade Will demo account; execution is enabled while risk is managed as if real.
// - The configured USD 500 is a virtual strategy budget, not a broker-side segregated balance.
// - If the broker/terminal mislabels IsDemo(), the mismatch is reported but does not block entries by default.
// - Set InpBlockOnAccountTypeMismatch=true if you want the mismatch to block all new entries.
// - Historical evidence is an in-sample diagnostic, not proof of future profitability.

enum EngineMode { OBSERVE_ONLY=0, AUTO_EXECUTION=1 };
enum AccountTypeReport { ACCOUNT_REPORT_AUTO=0, ACCOUNT_REPORT_DEMO_CONFIRMED=1, ACCOUNT_REPORT_REAL_CONFIRMED=2 };
enum ModelId { MODEL_TREND=0, MODEL_MOMENTUM=1, MODEL_DONCHIAN=2, MODEL_MEANREV=3, MODEL_PULLBACK=4 };

input EngineMode InpMode = AUTO_EXECUTION;
input int      InpMagic = 2036130;
// User-confirmed Trade Will demo account. Risk rules remain identical to real-style risk management.
input AccountTypeReport InpAccountTypeReport = ACCOUNT_REPORT_DEMO_CONFIRMED;
input bool     InpBlockOnAccountTypeMismatch = false;
input double   InpOperatingCapitalUSD = 500.0;
input double   InpRiskPerTradeUSD = 1.25;
input double   InpHardRiskCapUSD = 2.00;
input double   InpDailyLossLimitUSD = 10.00;
input int      InpMaxTradesPerDay = 3;
input int      InpMaxOpenTrades = 1;
input int      InpMaxSpreadPoints = 35;
input double   InpCampaignLossStopUSD = 50.00;
input double   InpStrictLossThresholdUSD = 25.00;
input double   InpProfitFlexThresholdUSD = 50.00;
input double   InpProfitProtectThresholdUSD = 100.00;
input int      InpResetGovernorToken = 0; // Increment once to reset a latched -$50 campaign stop and start a new campaign.
input int      InpSlippagePoints = 10;
input bool     InpWriteCSV = true;
input bool     InpPrintDiagnostics = true;

// Optional reporting to the SBT Worker. Add the workers.dev origin to MT4 Tools > Options > Expert Advisors > Allow WebRequest. Reporting is read-only and never controls execution.
input bool     InpSbtTelemetryEnabled = true;
input string   InpSbtTelemetryURL = "https://bitey-system-bots-trading.raylerr481.workers.dev/api/v1/mt4/bitey-report";
input string   InpSbtToken = "";
input int      InpSbtTelemetryTimeoutMs = 1500;
input bool     InpSbtClosedTradeReportsEnabled = true;
input string   InpSbtClosedTradeURL = "https://bitey-system-bots-trading.raylerr481.workers.dev/api/v1/mt4/trade-closed";
input bool     InpQlearningExperienceEnabled = true; // Sends realized transitions; SBT backend owns learning updates.

// Effective strategy capital is capped at the configured allocation and never
// assumes more available capital than the account equity. This is a virtual
// risk budget, not a segregated broker sub-account. Account currency must be USD.
double EffectiveOperatingCapitalUSD()
{
   if(AccountCurrency()!="USD") return 0.0;
   double balance=AccountBalance();
   double equity=AccountEquity();
   if(balance<=0.0 || equity<=0.0) return 0.0;
   // Use the lower of balance/equity so floating gains cannot inflate the budget
   // and floating losses immediately reduce the capital available to this strategy.
   return MathMin(InpOperatingCapitalUSD,MathMin(balance,equity));
}

double EffectiveDailyLossLimitUSD()
{
   double capital=EffectiveOperatingCapitalUSD();
   if(capital<=0.0) return 0.0;
   return MathMin(MathAbs(InpDailyLossLimitUSD),capital*0.02);
}

double EffectiveRiskBudgetUSD()
{
   double capital=EffectiveOperatingCapitalUSD();
   if(capital<=0.0) return 0.0;
   return MathMin(MathMin(InpRiskPerTradeUSD,InpHardRiskCapUSD),capital*0.004);
}

input int      InpATRPeriod = 14;
input double   InpStopATR = 1.30;
input double   InpTargetATR = 2.60;
input int      InpMaxHoldBars = 6;
input int      InpFastEMA = 8;
input int      InpSlowEMA = 21;
input int      InpTrendEMA = 200;
input int      InpRSIPeriod = 14;
input int      InpADXPeriod = 14;
input double   InpTrendADXMin = 18.0;
input int      InpDonchianPeriod = 20;
input int      InpMomentumLookback = 3;
input double   InpMomentumATRThreshold = 0.65;
input double   InpMeanRevADXMax = 18.0;
input double   InpMeanRevRSIBuy = 30.0;
input double   InpMeanRevRSISell = 70.0;
input double   InpPullbackMaxGapATR = 0.35;
input double   InpBreakoutBufferATR = 0.05;

input int      InpEvidenceLookbackBars = 240;
input int      InpForwardHorizonBars = 6;
input int      InpMinEvidenceSamples = 12;
input double   InpMinEvidenceWinRate = 0.42;
input double   InpMinEvidenceAvgR = 0.02;
input int      InpMinModelVotes = 1;

string   g_modelNames[5] = {"TREND","MOMENTUM","DONCHIAN","MEANREV","PULLBACK"};
datetime g_lastBarTime = 0;
string   g_currentBestStrategy = "NONE";
int      g_currentStateId = 0;
double   g_currentRiskBudgetUSD = 0.0;
// Persistent campaign risk governor. State values: 0 NORMAL, 1 STRICT,
// 2 PROFIT_FLEX, 3 PROFIT_PROTECT, 4 STOPPED_LOSS_LIMIT.
int      g_governorState = 0;
double   g_campaignStartTime = 0.0;
double   g_campaignNetUSD = 0.0;
string   g_governorBaseKey = "";

string GovernorKey(string suffix)
{
   return "BiteyRG_"+IntegerToString(AccountNumber())+"_"+IntegerToString(InpMagic)+"_"+IntegerToString(Period())+"_"+Symbol()+"_"+suffix;
}

bool AccountTypeMismatch()
{
   if(IsTesting()) return false;
   if(InpAccountTypeReport==ACCOUNT_REPORT_DEMO_CONFIRMED && !IsDemo()) return true;
   if(InpAccountTypeReport==ACCOUNT_REPORT_REAL_CONFIRMED && IsDemo()) return true;
   return false;
}

string ReportedAccountMode()
{
   if(IsTesting()) return "TESTER";
   if(InpAccountTypeReport==ACCOUNT_REPORT_DEMO_CONFIRMED) return "DEMO_CONFIRMED_BY_USER";
   if(InpAccountTypeReport==ACCOUNT_REPORT_REAL_CONFIRMED) return "REAL_CONFIRMED_BY_USER";
   return (IsDemo()?"DEMO_DETECTED_BY_TERMINAL":"REAL_OR_UNCLASSIFIED_BY_TERMINAL");
}

double CampaignNetProfitUSD()
{
   if(g_campaignStartTime<=0.0) return 0.0;
   double net=0.0;
   datetime start=(datetime)g_campaignStartTime;
   for(int i=OrdersHistoryTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_HISTORY)) continue;
      if(OrderSymbol()!=Symbol() || OrderMagicNumber()!=InpMagic) continue;
      if(OrderCloseTime()>=start) net+=OrderProfit()+OrderSwap()+OrderCommission();
   }
   for(int j=OrdersTotal()-1;j>=0;j--)
   {
      if(!OrderSelect(j,SELECT_BY_POS,MODE_TRADES)) continue;
      if(OrderSymbol()!=Symbol() || OrderMagicNumber()!=InpMagic) continue;
      if(OrderType()==OP_BUY || OrderType()==OP_SELL)
         net+=OrderProfit()+OrderSwap()+OrderCommission();
   }
   return net;
}

string GovernorStateName(int state)
{
   if(state==1) return "STRICT";
   if(state==2) return "PROFIT_FLEX";
   if(state==3) return "PROFIT_PROTECT";
   if(state==4) return "STOPPED_LOSS_LIMIT";
   return "NORMAL";
}

void UpdateRiskGovernor()
{
   if(g_campaignStartTime<=0.0)
   {
      string startKey=GovernorKey("START");
      if(GlobalVariableCheck(startKey)) g_campaignStartTime=GlobalVariableGet(startKey);
      else { g_campaignStartTime=(double)TimeCurrent(); GlobalVariableSet(startKey,g_campaignStartTime); }
   }
   string stopKey=GovernorKey("STOP");
   if(GlobalVariableCheck(stopKey) && GlobalVariableGet(stopKey)>=1.0)
   {
      // A latched stop is authoritative across EA/terminal restarts. Never clear it
      // merely because the terminal's loaded history temporarily reports less P/L.
      g_governorState=4;
      g_campaignNetUSD=CampaignNetProfitUSD();
      return;
   }
   g_campaignNetUSD=CampaignNetProfitUSD();
   int nextState=0;
   if(g_campaignNetUSD<=-MathAbs(InpCampaignLossStopUSD))
   {
      nextState=4;
      GlobalVariableSet(stopKey,1.0);
      GlobalVariableSet(GovernorKey("LOCK_TIME"),(double)TimeCurrent());
      GlobalVariableSet(GovernorKey("LOCK_NET"),g_campaignNetUSD);
      GlobalVariablesFlush();
      Print("RISK GOVERNOR LOCK PERSISTED | campaignNetUSD=",DoubleToString(g_campaignNetUSD,2),
            " threshold=-",DoubleToString(MathAbs(InpCampaignLossStopUSD),2),
            " | new entries disabled; lock saved to MT4 terminal Global Variables.");
   }
   else if(g_campaignNetUSD<=-MathAbs(InpStrictLossThresholdUSD)) nextState=1;
   else if(g_campaignNetUSD>=MathAbs(InpProfitProtectThresholdUSD)) nextState=3;
   else if(g_campaignNetUSD>=MathAbs(InpProfitFlexThresholdUSD)) nextState=2;
   if(nextState!=g_governorState)
   {
      g_governorState=nextState;
      Print("RISK GOVERNOR STATE | ",GovernorStateName(g_governorState),
            " | campaignNetUSD=",DoubleToString(g_campaignNetUSD,2),
            " | start=",TimeToString((datetime)g_campaignStartTime,TIME_DATE|TIME_SECONDS),
            " | newEntries=",(g_governorState==4?"LOCKED":"subject to gates"));
   }
   GlobalVariableSet(GovernorKey("STATE"),(double)g_governorState);
}

int RequiredModelVotes()
{
   if(g_governorState==1) return MathMax(2,InpMinModelVotes);
   return InpMinModelVotes;
}


struct DirectionEvidence
{
   int samples;
   int wins;
   double sumR;
   double winRate;
   double avgR;
};

void ResetEvidence(DirectionEvidence &e)
{
   e.samples=0; e.wins=0; e.sumR=0.0; e.winRate=0.0; e.avgR=0.0;
}

void FinalizeEvidence(DirectionEvidence &e)
{
   if(e.samples>0)
   {
      e.winRate=(double)e.wins/(double)e.samples;
      e.avgR=e.sumR/(double)e.samples;
   }
   else { e.winRate=0.0; e.avgR=0.0; }
}

int OnInit()
{
   if(InpOperatingCapitalUSD<=0 || InpRiskPerTradeUSD<=0 || InpHardRiskCapUSD<=0 || InpSbtTelemetryTimeoutMs<250 ||
      InpATRPeriod<2 || InpForwardHorizonBars<1 || InpEvidenceLookbackBars<30 ||
      InpPullbackMaxGapATR<0 || InpBreakoutBufferATR<0 || InpStopATR<=0 || InpTargetATR<=0 ||
      InpMinModelVotes<1 || InpMinModelVotes>5 || InpCampaignLossStopUSD<=0 || InpStrictLossThresholdUSD<=0 ||
      InpProfitFlexThresholdUSD<=0 || InpProfitProtectThresholdUSD<=0 || InpStrictLossThresholdUSD>=InpCampaignLossStopUSD ||
      InpProfitFlexThresholdUSD>=InpProfitProtectThresholdUSD)
   {
      Print("BITEY SBT v1.43 INIT ERROR: invalid risk or lookback inputs.");
      return(INIT_PARAMETERS_INCORRECT);
   }
   g_lastBarTime=0;
   string resetKey=GovernorKey("RESET_TOKEN");
   string startKey=GovernorKey("START");
   string stopKey=GovernorKey("STOP");
   if(!GlobalVariableCheck(resetKey)) GlobalVariableSet(resetKey,(double)InpResetGovernorToken);
   else if((int)GlobalVariableGet(resetKey)!=InpResetGovernorToken)
   {
      GlobalVariableSet(resetKey,(double)InpResetGovernorToken);
      GlobalVariableDel(stopKey);
      GlobalVariableSet(startKey,(double)TimeCurrent());
      GlobalVariableSet(GovernorKey("STATE"),0.0);
      GlobalVariableDel(GovernorKey("LOCK_TIME"));
      GlobalVariableDel(GovernorKey("LOCK_NET"));
      GlobalVariablesFlush();
      Print("RISK GOVERNOR RESET | token changed; new campaign started. This does not close any existing position.");
   }
   if(GlobalVariableCheck(startKey)) g_campaignStartTime=GlobalVariableGet(startKey);
   else { g_campaignStartTime=(double)TimeCurrent(); GlobalVariableSet(startKey,g_campaignStartTime); }
   if(GlobalVariableCheck(stopKey) && GlobalVariableGet(stopKey)>=1.0) g_governorState=4;
   UpdateRiskGovernor();
   if(g_governorState==4)
      Print("RISK GOVERNOR RESTORE CHECK | LOCKED after initialization | start=",
            TimeToString((datetime)g_campaignStartTime,TIME_DATE|TIME_SECONDS),
            " | campaignNetUSD=",DoubleToString(g_campaignNetUSD,2),
            " | lockTime=",(GlobalVariableCheck(GovernorKey("LOCK_TIME"))?TimeToString((datetime)GlobalVariableGet(GovernorKey("LOCK_TIME")),TIME_DATE|TIME_SECONDS):"legacy lock (timestamp unavailable)"),
            " | manual reset token required.");
   else
      Print("RISK GOVERNOR RESTORE CHECK | state=",GovernorStateName(g_governorState),
            " | start=",TimeToString((datetime)g_campaignStartTime,TIME_DATE|TIME_SECONDS),
            " | stopLatched=false | terminal Global Variables loaded.");
   Print("BITEY SBT Multi-Model Engine v1.44 initialized | Symbol=",Symbol(),
         " TF=",Period()," Mode=",(InpMode==OBSERVE_ONLY?"OBSERVE_ONLY":"AUTO_EXECUTION"),
         " AllocationCapUSD=",DoubleToString(InpOperatingCapitalUSD,2),
         " EffectiveCapitalUSD=",DoubleToString(EffectiveOperatingCapitalUSD(),2),
         " RiskRequestUSD=",DoubleToString(InpRiskPerTradeUSD,2),
         " HardRiskCapUSD=",DoubleToString(InpHardRiskCapUSD,2),
         " Governor=",GovernorStateName(g_governorState)," CampaignNetUSD=",DoubleToString(g_campaignNetUSD,2),
         " EffectiveDailyLossUSD=",DoubleToString(EffectiveDailyLossLimitUSD(),2),
         " AccountMode=",ReportedAccountMode(),
         " TerminalIsDemo=",(IsDemo()?"true":"false"),
         " AccountServer=",AccountServer(),
         " AccountCompany=",AccountCompany(),
         " AccountNumber=",IntegerToString(AccountNumber()),
         " GovernorStart=",TimeToString((datetime)g_campaignStartTime,TIME_DATE|TIME_SECONDS),
         " GovernorStopLatched=",(GlobalVariableCheck(stopKey) && GlobalVariableGet(stopKey)>=1.0?"true":"false"),
         " AccountTypeMismatchBlock=",(InpBlockOnAccountTypeMismatch?"true":"false"),
         " AccountTypeMismatch=",(AccountTypeMismatch()?"true":"false"),
         " AccountTypeFilter=none");
   if(AccountTypeMismatch())
      Print("ACCOUNT TYPE WARNING | User-confirmed demo report contradicts terminal IsDemo(). New entries ",(InpBlockOnAccountTypeMismatch?"WILL BE BLOCKED":"are allowed by override"),". Verify broker account classification before trading.");
   if(InpSbtTelemetryEnabled)
   {
      Print("SBT TELEMETRY CONFIG | SnapshotURL=",InpSbtTelemetryURL);
      if(InpSbtClosedTradeReportsEnabled)
         Print("SBT TELEMETRY CONFIG | ClosedTradeURL=",InpSbtClosedTradeURL);
      Print("SBT TELEMETRY REQUIREMENT | In MT4 open Tools > Options > Expert Advisors, enable Allow WebRequest for listed URL, and add exactly: https://bitey-system-bots-trading.raylerr481.workers.dev");
   }
   if(InpWriteCSV) EnsureCSVHeader();
   return(INIT_SUCCEEDED);
}

void OnTick()
{
   if(Bars < InpTrendEMA+InpDonchianPeriod+InpForwardHorizonBars+20) return;
   datetime barTime=iTime(Symbol(),Period(),0);
   UpdateRiskGovernor();
   if(barTime==0 || barTime==g_lastBarTime) return;
   g_lastBarTime=barTime;
   int closedByTime=ManageOpenTrades();
   SyncClosedTrades();
   if(closedByTime>0)
   {
      Print("ENTRY SKIPPED | time exit processed; next entry evaluation waits for next bar.");
      return;
   }
   EvaluateEngine();
}

void EnsureCSVHeader()
{
   int h=FileOpen("Bitey_SBT_Evidence_v1_43.csv",FILE_CSV|FILE_READ|FILE_WRITE|FILE_SHARE_READ,';');
   if(h==INVALID_HANDLE) { Print("CSV warning: cannot open evidence file. Error=",GetLastError()); return; }
   if(FileSize(h)==0)
      FileWrite(h,"time","symbol","timeframe","model","direction","samples","win_rate","avg_R","signal","decision");
   FileClose(h);
}

void WriteEvidenceRow(string model,string direction,DirectionEvidence &e,int signal,string decision)
{
   if(!InpWriteCSV) return;
   int h=FileOpen("Bitey_SBT_Evidence_v1_43.csv",FILE_CSV|FILE_READ|FILE_WRITE|FILE_SHARE_READ,';');
   if(h==INVALID_HANDLE) return;
   FileSeek(h,0,SEEK_END);
   FileWrite(h,TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS),Symbol(),IntegerToString(Period()),model,direction,
             IntegerToString(e.samples),DoubleToString(e.winRate,4),DoubleToString(e.avgR,4),IntegerToString(signal),decision);
   FileClose(h);
}

string JsonEscape(string value)
{
   StringReplace(value, "\\", "\\\\");
   StringReplace(value, "\"", "\\\"");
   StringReplace(value, "\r", "\\r");
   StringReplace(value, "\n", "\\n");
   return value;
}

string JsonBool(bool value) { return value ? "true" : "false"; }

// Serialize a single evidence record through a reference. Keeping field access
// inside this helper avoids MQL4's false-positive warning on struct arrays.
string EvidenceToJson(DirectionEvidence &e)
{
   bool passed=(e.samples>=InpMinEvidenceSamples &&
                e.winRate>=InpMinEvidenceWinRate &&
                e.avgR>InpMinEvidenceAvgR);
   return "{\"n\":"+IntegerToString(e.samples)+
          ",\"win_rate\":"+DoubleToString(e.winRate,4)+
          ",\"avg_r\":"+DoubleToString(e.avgR,6)+
          ",\"pass\":"+JsonBool(passed)+"}";
}

string CurrentRegime(double closePrice,double emaTrend,double adx)
{
   if(adx < InpTrendADXMin) return "RANGE_OR_WEAK_TREND";
   if(closePrice > emaTrend) return "TREND_UP";
   if(closePrice < emaTrend) return "TREND_DOWN";
   return "TRANSITION";
}

void SendSbtSnapshot(int decision,string decisionText,int buyVotes,int sellVotes,
                     int trend,int momentum,int donchian,int meanrev,int pullback,
                     string modelsJson,string bestStrategy,double bestScore,
                     double closePrice,double emaFast,double emaSlow,double emaTrend,
                     double rsi,double adx,double atr,bool riskGateAllowed,
                     string riskGateReason,string executionResult)
{
   if(!InpSbtTelemetryEnabled || StringLen(InpSbtTelemetryURL)==0) return;

   RefreshRates();
   string direction = decision>0 ? "BUY" : (decision<0 ? "SELL" : "HOLD");
   string mode = InpMode==AUTO_EXECUTION ? "AUTO_EXECUTION" : "OBSERVE_ONLY";
   string accountMode = ReportedAccountMode();
   double riskBudget = EffectiveRiskBudgetUSD();
   double spreadPoints = MarketInfo(Symbol(),MODE_SPREAD);

   string body="{";
   body+="\"source\":\"Bitey_SBT_MultiModel_Engine_v1_43\",";
   body+="\"symbol\":\""+JsonEscape(Symbol())+"\",";
   body+="\"timeframe\":\""+IntegerToString(Period())+"\",";
   body+="\"chart_timeframe\":\""+IntegerToString(Period())+"\",";
   body+="\"timestamp\":\""+JsonEscape(TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS))+"\",";
   body+="\"mode\":\""+mode+"\",";
   body+="\"execution_enabled\":"+JsonBool(InpMode==AUTO_EXECUTION)+",";
   body+="\"report_type\":\"live_snapshot\",";
   body+="\"regime\":\""+CurrentRegime(closePrice,emaTrend,adx)+"\",";
   body+="\"best_strategy\":\""+JsonEscape(bestStrategy)+"\",";
   body+="\"best_score\":"+DoubleToString(bestScore,6)+",";
   body+="\"metrics\":{";
   body+="\"engine_version\":\"1.43\",";
   body+="\"magic\":"+IntegerToString(InpMagic)+",";
   body+="\"decision\":\""+JsonEscape(decisionText)+"\",";
   body+="\"direction\":\""+direction+"\",";
   body+="\"buy_votes\":"+IntegerToString(buyVotes)+",";
   body+="\"sell_votes\":"+IntegerToString(sellVotes)+",";
   body+="\"signals\":{\"trend\":"+IntegerToString(trend)+",\"momentum\":"+IntegerToString(momentum)+",\"donchian\":"+IntegerToString(donchian)+",\"meanrev\":"+IntegerToString(meanrev)+",\"pullback\":"+IntegerToString(pullback)+"},";
   body+="\"models\":"+modelsJson+",";
   body+="\"spread_points\":"+DoubleToString(spreadPoints,1)+",";
   body+="\"risk_budget_usd\":"+DoubleToString(riskBudget,2)+",";
   body+="\"risk_request_usd\":"+DoubleToString(InpRiskPerTradeUSD,2)+",";
   body+="\"hard_risk_cap_usd\":"+DoubleToString(InpHardRiskCapUSD,2)+",";
   body+="\"operating_capital_usd\":"+DoubleToString(EffectiveOperatingCapitalUSD(),2)+",";
   body+="\"campaign_net_usd\":"+DoubleToString(g_campaignNetUSD,2)+",";
   body+="\"governor_state\":\""+GovernorStateName(g_governorState)+"\",";
   body+="\"campaign_loss_stop_usd\":"+DoubleToString(InpCampaignLossStopUSD,2)+",";
   body+="\"daily_loss_limit_usd\":"+DoubleToString(EffectiveDailyLossLimitUSD(),2)+",";
   body+="\"max_trades_per_day\":"+IntegerToString(InpMaxTradesPerDay)+",";
   body+="\"max_open_trades\":"+IntegerToString(InpMaxOpenTrades)+",";
   body+="\"trades_today\":"+IntegerToString(CountTodayTrades())+",";
   body+="\"positions_open\":"+IntegerToString(CountOpenTrades())+",";
   body+="\"ema_fast\":"+DoubleToString(emaFast,Digits)+",";
   body+="\"ema_slow\":"+DoubleToString(emaSlow,Digits)+",";
   body+="\"ema_200\":"+DoubleToString(emaTrend,Digits)+",";
   body+="\"close\":"+DoubleToString(closePrice,Digits)+",";
   body+="\"rsi\":"+DoubleToString(rsi,4)+",";
   body+="\"adx\":"+DoubleToString(adx,4)+",";
   body+="\"atr\":"+DoubleToString(atr,Digits+2)+",";
   body+="\"execution_result\":\""+JsonEscape(executionResult)+"\"},";
   body+="\"strategies\":"+modelsJson+",";
   body+="\"market\":{";
   body+="\"bid\":"+DoubleToString(Bid,Digits)+",";
   body+="\"ask\":"+DoubleToString(Ask,Digits)+",";
   body+="\"close\":"+DoubleToString(closePrice,Digits)+",";
   body+="\"ema_fast\":"+DoubleToString(emaFast,Digits)+",";
   body+="\"ema_slow\":"+DoubleToString(emaSlow,Digits)+",";
   body+="\"ema_200\":"+DoubleToString(emaTrend,Digits)+",";
   body+="\"atr\":"+DoubleToString(atr,Digits+2)+",";
   body+="\"rsi\":"+DoubleToString(rsi,4)+",";
   body+="\"adx\":"+DoubleToString(adx,4)+",";
   body+="\"spread_points\":"+DoubleToString(spreadPoints,1)+"},";
   body+="\"account\":{";
   body+="\"mode\":\""+accountMode+"\",";
   body+="\"terminal_is_demo\":"+JsonBool(IsDemo())+",";
   body+="\"server\":\""+JsonEscape(AccountServer())+"\",";
   body+="\"company\":\""+JsonEscape(AccountCompany())+"\",";
   body+="\"balance\":"+DoubleToString(AccountBalance(),2)+",";
   body+="\"equity\":"+DoubleToString(AccountEquity(),2)+",";
   body+="\"currency\":\""+JsonEscape(AccountCurrency())+"\",";
   body+="\"position_count\":"+IntegerToString(CountOpenTrades())+",";
   body+="\"operational_capital_usd\":"+DoubleToString(EffectiveOperatingCapitalUSD(),2)+"},";
   body+="\"risk_gate\":{";
   body+="\"allowed\":"+JsonBool(riskGateAllowed)+",";
   body+="\"reason\":\""+JsonEscape(riskGateReason)+"\",";
   body+="\"risk_budget_usd\":"+DoubleToString(riskBudget,2)+",";
   body+="\"hard_risk_cap_usd\":"+DoubleToString(InpHardRiskCapUSD,2)+",";
   body+="\"campaign_net_usd\":"+DoubleToString(g_campaignNetUSD,2)+",";
   body+="\"governor_state\":\""+GovernorStateName(g_governorState)+"\",";
   body+="\"campaign_loss_stop_usd\":"+DoubleToString(InpCampaignLossStopUSD,2)+",";
   body+="\"daily_loss_limit_usd\":"+DoubleToString(EffectiveDailyLossLimitUSD(),2)+",";
   body+="\"scope\":\"EA symbol and magic only; not account-wide\"},";
   body+="\"learning\":{";
   body+="\"framework\":\"Q_LEARNING\",";
   body+="\"policy_key\":\"bitey_shared_trading_q_v1\",";
   body+="\"learning_scope\":\"shared_bitey_ia_sbt\",";
   body+="\"experience_source\":\"realized_trade_closures\",";
   body+="\"state_id\":"+IntegerToString(BuildStateId(closePrice,emaFast,emaSlow,emaTrend,rsi,adx,atr))+",";
   body+="\"action\":\""+direction+"\",";
   body+="\"reward_available\":false,";
   body+="\"update_policy\":\"closed_trade_only_backend_owned\"},";
   body+="\"bot\":{";
   body+="\"name\":\"Bitey SBT Multi-Model Engine\",";
   body+="\"id\":\"bitey-sbt-multimodel\",";
   body+="\"version\":\"1.43\",";
   body+="\"magic\":"+IntegerToString(InpMagic)+",";
   body+="\"strategy\":\"ENSEMBLE\",";
   body+="\"signal\":\""+direction+"\",";
   body+="\"active\":true}}";

   char post[],result[];
   StringToCharArray(body,post,0,StringLen(body),CP_UTF8);
   string headers="Content-Type: application/json; charset=utf-8\r\n";
   if(StringLen(InpSbtToken)>0) headers+="X-MT4-Token: "+InpSbtToken+"\r\n";
   string responseHeaders="";
   ResetLastError();
   int status=WebRequest("POST",InpSbtTelemetryURL,headers,InpSbtTelemetryTimeoutMs,post,result,responseHeaders);
   int err=GetLastError();
   if(status>=200 && status<300)
      Print("SBT TELEMETRY OK | HTTP=",status," decision=",direction," result=",executionResult);
   else
   {
      if(err==4060)
         Print("SBT TELEMETRY BLOCKED BY MT4 | error=4060 ERR_FUNCTION_NOT_ALLOWED. Add the Worker origin to Tools > Options > Expert Advisors > Allow WebRequest for listed URL: https://bitey-system-bots-trading.raylerr481.workers.dev . This terminal permission cannot be enabled by EA code.");
      else
         Print("SBT TELEMETRY ERROR | HTTP=",status," error=",err," url=",InpSbtTelemetryURL," response=",CharArrayToString(result));
   }
}

int BuildStateId(double closePrice,double emaFast,double emaSlow,double emaTrend,double rsi,double adx,double atr)
{
   int trendBucket=(closePrice>emaTrend?2:(closePrice<emaTrend?0:1));
   int momentumBucket=(emaFast>emaSlow?2:(emaFast<emaSlow?0:1));
   int rsiBucket=(int)MathMin(4,MathMax(0,MathFloor(rsi/20.0)));
   int adxBucket=(adx<InpTrendADXMin?0:(adx<25.0?1:2));
   double atrPct=(closePrice>0?10000.0*atr/closePrice:0.0);
   int volatilityBucket=(atrPct<5.0?0:(atrPct<10.0?1:2));
   return trendBucket*10000+momentumBucket*1000+rsiBucket*100+adxBucket*10+volatilityBucket;
}

int StrategyCode(string name)
{
   for(int i=0;i<5;i++) if(name==g_modelNames[i]) return i+1;
   return 0;
}

string StrategyFromCode(int code)
{
   if(code>=1 && code<=5) return g_modelNames[code-1];
   return "UNKNOWN";
}

string TicketGlobalKey(string suffix,int ticket)
{
   return "B38_"+IntegerToString(AccountNumber())+"_"+IntegerToString(InpMagic)+"_"+IntegerToString(ticket)+"_"+suffix;
}

void StoreEntryExperience(int ticket,int direction,double actualRiskUSD)
{
   GlobalVariableSet(TicketGlobalKey("state",ticket),(double)g_currentStateId);
   GlobalVariableSet(TicketGlobalKey("model",ticket),(double)StrategyCode(g_currentBestStrategy));
   GlobalVariableSet(TicketGlobalKey("risk",ticket),actualRiskUSD);
   GlobalVariableSet(TicketGlobalKey("action",ticket),(double)(direction>0?1:-1));
}

string ExitReasonForSelectedOrder()
{
   double closePrice=OrderClosePrice();
   double sl=OrderStopLoss();
   double tp=OrderTakeProfit();
   double tolerance=MathMax(Point*3.0,MarketInfo(OrderSymbol(),MODE_TICKSIZE)*3.0);
   if(sl>0 && MathAbs(closePrice-sl)<=tolerance) return "STOP_LOSS";
   if(tp>0 && MathAbs(closePrice-tp)<=tolerance) return "TAKE_PROFIT";
   return "TIME_OR_MANUAL_OR_OTHER";
}

bool SendClosedTradeReport(int historyIndex)
{
   if(!InpSbtClosedTradeReportsEnabled || StringLen(InpSbtClosedTradeURL)<10) return false;
   if(!OrderSelect(historyIndex,SELECT_BY_POS,MODE_HISTORY)) return false;
   if(OrderSymbol()!=Symbol() || OrderMagicNumber()!=InpMagic) return false;
   if(OrderType()!=OP_BUY && OrderType()!=OP_SELL) return false;
   int ticket=OrderTicket();
   string sentKey=TicketGlobalKey("sent",ticket);
   if(GlobalVariableCheck(sentKey) && GlobalVariableGet(sentKey)>0) return true;

   double netPnl=OrderProfit()+OrderCommission()+OrderSwap();
   string stateKey=TicketGlobalKey("state",ticket);
   string modelKey=TicketGlobalKey("model",ticket);
   string riskKey=TicketGlobalKey("risk",ticket);
   string actionKey=TicketGlobalKey("action",ticket);
   bool hasEntryState=GlobalVariableCheck(stateKey) && GlobalVariableCheck(riskKey) && GlobalVariableCheck(actionKey);
   int entryState=(hasEntryState?(int)GlobalVariableGet(stateKey):0);
   int modelCode=(GlobalVariableCheck(modelKey)?(int)GlobalVariableGet(modelKey):0);
   double riskUSD=(GlobalVariableCheck(riskKey)?GlobalVariableGet(riskKey):0.0);
   double rewardR=(riskUSD>0.0?netPnl/riskUSD:0.0);
   int direction=(OrderType()==OP_BUY?1:-1);
   string side=(direction>0?"BUY":"SELL");
   int closeShift=iBarShift(Symbol(),Period(),OrderCloseTime(),false);
   if(closeShift<1) closeShift=1;
   double close1=iClose(Symbol(),Period(),closeShift);
   double emaFast=iMA(Symbol(),Period(),InpFastEMA,0,MODE_EMA,PRICE_CLOSE,closeShift);
   double emaSlow=iMA(Symbol(),Period(),InpSlowEMA,0,MODE_EMA,PRICE_CLOSE,closeShift);
   double emaTrend=iMA(Symbol(),Period(),InpTrendEMA,0,MODE_EMA,PRICE_CLOSE,closeShift);
   double rsi=iRSI(Symbol(),Period(),InpRSIPeriod,PRICE_CLOSE,closeShift);
   double adx=iADX(Symbol(),Period(),InpADXPeriod,PRICE_CLOSE,MODE_MAIN,closeShift);
   double atr=GetATR(closeShift);
   int nextState=BuildStateId(close1,emaFast,emaSlow,emaTrend,rsi,adx,atr);
   string model=StrategyFromCode(modelCode);
   string body="{";
   body+="\"source\":\"MT4_DESKTOP\",";
   body+="\"bot_id\":\"BITEY_SBT_MULTIMODEL\",";
   body+="\"strategy\":\""+JsonEscape(model)+"\",";
   body+="\"version\":\"1.43\",";
   body+="\"ticket\":"+IntegerToString(ticket)+",";
   body+="\"magic\":"+IntegerToString(OrderMagicNumber())+",";
   body+="\"symbol\":\""+JsonEscape(OrderSymbol())+"\",";
   body+="\"timeframe\":\""+IntegerToString(Period())+"\",";
   body+="\"side\":\""+side+"\",";
   body+="\"lots\":"+DoubleToString(OrderLots(),2)+",";
   body+="\"open_time\":\""+TimeToString(OrderOpenTime(),TIME_DATE|TIME_SECONDS)+"\",";
   body+="\"close_time\":\""+TimeToString(OrderCloseTime(),TIME_DATE|TIME_SECONDS)+"\",";
   body+="\"open_price\":"+DoubleToString(OrderOpenPrice(),Digits)+",";
   body+="\"close_price\":"+DoubleToString(OrderClosePrice(),Digits)+",";
   body+="\"stop_loss\":"+DoubleToString(OrderStopLoss(),Digits)+",";
   body+="\"take_profit\":"+DoubleToString(OrderTakeProfit(),Digits)+",";
   body+="\"pnl\":"+DoubleToString(netPnl,2)+",";
   body+="\"commission\":"+DoubleToString(OrderCommission(),2)+",";
   body+="\"swap\":"+DoubleToString(OrderSwap(),2)+",";
   body+="\"exit_reason\":\""+ExitReasonForSelectedOrder()+"\",";
   body+="\"r_multiple\":"+DoubleToString(rewardR,5)+",";
   body+="\"metadata\":{";
   body+="\"report_family\":\"BITEY_SBT_LIBRARY\",";
   body+="\"learning_scope\":\"shared_bitey_ia_sbt\",";
   body+="\"source_version\":\"1.43\",";
   body+="\"q_learning\":{";
   body+="\"algorithm\":\"Q_LEARNING\",";
   body+="\"policy_key\":\"bitey_shared_trading_q_v1\",";
   body+="\"eligible\":"+JsonBool(InpQlearningExperienceEnabled && hasEntryState && riskUSD>0)+",";
   body+="\"state_id\":"+IntegerToString(entryState)+",";
   body+="\"action\":\""+side+"\",";
   body+="\"reward_r\":"+DoubleToString(rewardR,5)+",";
   body+="\"next_state_id\":"+IntegerToString(nextState)+",";
   body+="\"terminal\":true,";
   body+="\"model\":\""+JsonEscape(model)+"\",";
   body+="\"costs_included\":true,";
   body+="\"update_policy\":\"backend_owned_not_client_assumed\",";
   body+="\"ineligible_reason\":\""+(hasEntryState?"":"entry_state_missing_after_restart_or_legacy_trade")+"\"}}}";

   char post[],result[];
   StringToCharArray(body,post,0,StringLen(body),CP_UTF8);
   string headers="Content-Type: application/json; charset=utf-8\r\n";
   if(StringLen(InpSbtToken)>0) headers+="X-MT4-Token: "+InpSbtToken+"\r\n";
   string responseHeaders="";
   ResetLastError();
   int status=WebRequest("POST",InpSbtClosedTradeURL,headers,InpSbtTelemetryTimeoutMs,post,result,responseHeaders);
   int err=GetLastError();
   if(status>=200 && status<300)
   {
      GlobalVariableSet(sentKey,1.0);
      if(GlobalVariableCheck(stateKey)) GlobalVariableDel(stateKey);
      if(GlobalVariableCheck(modelKey)) GlobalVariableDel(modelKey);
      if(GlobalVariableCheck(riskKey)) GlobalVariableDel(riskKey);
      if(GlobalVariableCheck(actionKey)) GlobalVariableDel(actionKey);
      Print("SBT CLOSED TRADE REPORT OK | ticket=",ticket," HTTP=",status,
            " net=",DoubleToString(netPnl,2)," R=",DoubleToString(rewardR,4),
            " QLearningEligible=",(InpQlearningExperienceEnabled && hasEntryState && riskUSD>0?"YES":"NO"));
      return true;
   }
   if(err==4060)
      Print("SBT CLOSED TRADE REPORT BLOCKED BY MT4 | ticket=",ticket," error=4060 ERR_FUNCTION_NOT_ALLOWED. Add the Worker origin to Tools > Options > Expert Advisors > Allow WebRequest for listed URL: https://bitey-system-bots-trading.raylerr481.workers.dev . The closed trade will be retried while it remains in history.");
   else
      Print("SBT CLOSED TRADE REPORT ERROR | ticket=",ticket," HTTP=",status," error=",err,
            " url=",InpSbtClosedTradeURL," response=",CharArrayToString(result));
   return false;
}

void SyncClosedTrades()
{
   int total=OrdersHistoryTotal();
   for(int i=total-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_HISTORY)) continue;
      if(OrderSymbol()!=Symbol() || OrderMagicNumber()!=InpMagic) continue;
      if(OrderType()!=OP_BUY && OrderType()!=OP_SELL) continue;
      string sentKey=TicketGlobalKey("sent",OrderTicket());
      if(GlobalVariableCheck(sentKey) && GlobalVariableGet(sentKey)>0) continue;
      if(!SendClosedTradeReport(i)) break; // avoid hammering an unavailable backend
   }
}

int ManageOpenTrades()
{
   int closedCount=0;
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      if(OrderSymbol()!=Symbol() || OrderMagicNumber()!=InpMagic) continue;
      int type=OrderType();
      if(type!=OP_BUY && type!=OP_SELL) continue;
      int barsOpen=iBarShift(Symbol(),Period(),OrderOpenTime(),false);
      if(barsOpen<0 || barsOpen<InpMaxHoldBars) continue;
      RefreshRates();
      double closePrice=NormalizeDouble(type==OP_BUY?Bid:Ask,Digits);
      int ticket=OrderTicket();
      double lots=OrderLots();
      ResetLastError();
      if(OrderClose(ticket,lots,closePrice,InpSlippagePoints,clrNONE))
      {
         closedCount++;
         Print("TIME EXIT | ticket=",ticket," direction=",(type==OP_BUY?"BUY":"SELL"),
               " barsOpen=",barsOpen," maxHoldBars=",InpMaxHoldBars,
               " closePrice=",DoubleToString(closePrice,Digits));
      }
      else Print("TIME EXIT FAILED | ticket=",ticket," barsOpen=",barsOpen," error=",GetLastError());
   }
   return closedCount;
}

double GetATR(int shift)
{
   return iATR(Symbol(),Period(),InpATRPeriod,shift);
}

int SignOf(double x,double tolerance)
{
   if(x>tolerance) return 1;
   if(x< -tolerance) return -1;
   return 0;
}

bool GetModelSignals(int shift,int &trend,int &momentum,int &donchian,int &meanrev,int &pullback)
{
   trend=0; momentum=0; donchian=0; meanrev=0; pullback=0;
   if(Bars < InpTrendEMA+InpDonchianPeriod+shift+InpMomentumLookback+5) return false;
   double close1=iClose(Symbol(),Period(),shift);
   double atr=GetATR(shift);
   double emaFast=iMA(Symbol(),Period(),InpFastEMA,0,MODE_EMA,PRICE_CLOSE,shift);
   double emaSlow=iMA(Symbol(),Period(),InpSlowEMA,0,MODE_EMA,PRICE_CLOSE,shift);
   double emaTrend=iMA(Symbol(),Period(),InpTrendEMA,0,MODE_EMA,PRICE_CLOSE,shift);
   double adx=iADX(Symbol(),Period(),InpADXPeriod,PRICE_CLOSE,MODE_MAIN,shift);
   double plusDI=iADX(Symbol(),Period(),InpADXPeriod,PRICE_CLOSE,MODE_PLUSDI,shift);
   double minusDI=iADX(Symbol(),Period(),InpADXPeriod,PRICE_CLOSE,MODE_MINUSDI,shift);
   double rsi=iRSI(Symbol(),Period(),InpRSIPeriod,PRICE_CLOSE,shift);
   if(close1<=0 || atr<=0 || emaFast<=0 || emaSlow<=0 || emaTrend<=0) return false;

   if(adx>=InpTrendADXMin)
   {
      // Standard directional trend confirmation.
      if(close1>emaTrend && emaFast>emaSlow && plusDI>minusDI) trend=1;
      else if(close1<emaTrend && emaFast<emaSlow && minusDI>plusDI) trend=-1;
      else
      {
         // Pullback continuation: price remains on the correct side of EMA200,
         // ADX is strong, directional DI confirms the trend, and price is near EMA21.
         // This can recognize a retracement without treating every retracement as a reversal.
         double emaGap=MathAbs(close1-emaSlow);
         if(close1<emaTrend && minusDI>plusDI && emaGap<=0.25*atr) trend=-1;
         else if(close1>emaTrend && plusDI>minusDI && emaGap<=0.25*atr) trend=1;
      }
   }

   int momShift=shift+InpMomentumLookback;
   double oldClose=iClose(Symbol(),Period(),momShift);
   if(oldClose>0)
   {
      double normalized=(close1-oldClose)/atr;
      if(normalized>=InpMomentumATRThreshold && close1>emaSlow) momentum=1;
      else if(normalized<=-InpMomentumATRThreshold && close1<emaSlow) momentum=-1;
   }

   double priorHigh=-1.0e100, priorLow=1.0e100;
   for(int k=shift+1;k<=shift+InpDonchianPeriod;k++)
   {
      double hi=iHigh(Symbol(),Period(),k), lo=iLow(Symbol(),Period(),k);
      if(hi>priorHigh) priorHigh=hi;
      if(lo<priorLow) priorLow=lo;
   }
   double breakoutBuffer=MathMax(0.0,InpBreakoutBufferATR)*atr;
   if(close1>priorHigh+breakoutBuffer) donchian=1;
   else if(close1<priorLow-breakoutBuffer) donchian=-1;

   if(adx<=InpMeanRevADXMax)
   {
      if(rsi<=InpMeanRevRSIBuy) meanrev=1;
      else if(rsi>=InpMeanRevRSISell) meanrev=-1;
   }

   // Separate pullback-continuation model. It requires trend structure, DI confirmation,
   // and a closed candle reclaim/rejection around EMA21. It is not a blind EMA touch.
   double gapATR=MathAbs(close1-emaSlow)/atr;
   double close2=iClose(Symbol(),Period(),shift+1);
   double emaSlow2=iMA(Symbol(),Period(),InpSlowEMA,0,MODE_EMA,PRICE_CLOSE,shift+1);
   if(adx>=InpTrendADXMin && gapATR<=InpPullbackMaxGapATR && close2>0 && emaSlow2>0)
   {
      if(close1>emaTrend && emaTrend>iMA(Symbol(),Period(),InpTrendEMA,0,MODE_EMA,PRICE_CLOSE,shift+5)
         && plusDI>minusDI && close1>emaSlow && close2<=emaSlow2)
         pullback=1;
      else if(close1<emaTrend && emaTrend<iMA(Symbol(),Period(),InpTrendEMA,0,MODE_EMA,PRICE_CLOSE,shift+5)
              && minusDI>plusDI && close1<emaSlow && close2>=emaSlow2)
         pullback=-1;
   }
   return true;
}

// Returns the realized forward outcome in R for a hypothetical entry at the closed bar close.
// If stop and target are both touched inside one candle, the conservative result is -1R.
bool ForwardOutcomeR(int entryShift,int direction,double &outR)
{
   outR=0.0;
   double entry=iClose(Symbol(),Period(),entryShift);
   double atr=GetATR(entryShift);
   if(entry<=0 || atr<=0 || direction==0) return false;
   double riskDistance=atr*InpStopATR;
   double targetDistance=atr*InpTargetATR;
   if(riskDistance<=0 || targetDistance<=0) return false;
   int endShift=entryShift-InpForwardHorizonBars;
   if(endShift<0) endShift=0;
   for(int s=entryShift-1;s>=endShift;s--)
   {
      if(s<0) break;
      double hi=iHigh(Symbol(),Period(),s), lo=iLow(Symbol(),Period(),s);
      bool hitSL=false, hitTP=false;
      if(direction>0)
      {
         hitSL=(lo<=entry-riskDistance); hitTP=(hi>=entry+targetDistance);
      }
      else
      {
         hitSL=(hi>=entry+riskDistance); hitTP=(lo<=entry-targetDistance);
      }
      if(hitSL && hitTP) { outR=-1.0; return true; }
      if(hitSL) { outR=-1.0; return true; }
      if(hitTP) { outR=InpTargetATR/InpStopATR; return true; }
   }
   // Exit at the close of the final forward bar, normalized by the initial stop distance.
   double exitClose=iClose(Symbol(),Period(),endShift);
   if(exitClose<=0) return false;
   outR=(direction>0 ? (exitClose-entry) : (entry-exitClose))/riskDistance;
   return true;
}

int ModelSignalAt(int model,int shift)
{
   int t=0,m=0,d=0,r=0,p=0;
   if(!GetModelSignals(shift,t,m,d,r,p)) return 0;
   if(model==MODEL_TREND) return t;
   if(model==MODEL_MOMENTUM) return m;
   if(model==MODEL_DONCHIAN) return d;
   if(model==MODEL_MEANREV) return r;
   if(model==MODEL_PULLBACK) return p;
   return 0;
}

void BuildEvidence(int model,int direction,DirectionEvidence &e)
{
   ResetEvidence(e);
   int maxShift=MathMin(InpEvidenceLookbackBars,Bars-InpTrendEMA-InpDonchianPeriod-InpForwardHorizonBars-5);
   int minShift=InpForwardHorizonBars+1;
   for(int shift=minShift;shift<=maxShift;shift++)
   {
      if(ModelSignalAt(model,shift)!=direction) continue;
      double resultR=0.0;
      if(!ForwardOutcomeR(shift,direction,resultR)) continue;
      e.samples++;
      if(resultR>0.0) e.wins++;
      e.sumR+=resultR;
   }
   FinalizeEvidence(e);
}

bool EvidencePass(DirectionEvidence &e)
{
   int minSamples=InpMinEvidenceSamples;
   double minWinRate=InpMinEvidenceWinRate;
   double minAvgR=InpMinEvidenceAvgR;
   if(g_governorState==1)
   {
      minSamples=MathMax(InpMinEvidenceSamples,18);
      minWinRate=MathMax(InpMinEvidenceWinRate,0.48);
      minAvgR=MathMax(InpMinEvidenceAvgR,0.05);
   }
   else if(g_governorState==2)
   {
      minSamples=MathMax(8,MathMin(InpMinEvidenceSamples,10));
      minWinRate=MathMax(0.40,InpMinEvidenceWinRate-0.02);
      minAvgR=MathMax(0.01,InpMinEvidenceAvgR-0.005);
   }
   else if(g_governorState==3)
   {
      // Small relaxation only: preserve positive expectancy and a minimum sample.
      minSamples=MathMax(10,MathMin(InpMinEvidenceSamples,12));
      minWinRate=MathMax(0.40,InpMinEvidenceWinRate-0.02);
      minAvgR=MathMax(0.015,InpMinEvidenceAvgR-0.002);
   }
   return (e.samples>=minSamples && e.winRate>=minWinRate && e.avgR>minAvgR);
}

bool IsNewCalendarDay(datetime a,datetime b)
{
   if(a<=0 || b<=0) return true;
   return (TimeYear(a)!=TimeYear(b) || TimeMonth(a)!=TimeMonth(b) || TimeDay(a)!=TimeDay(b));
}

int CountTodayTrades()
{
   int count=0;
   datetime dayStart=StrToTime(TimeToString(TimeCurrent(),TIME_DATE));
   for(int i=OrdersHistoryTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_HISTORY)) continue;
      if(OrderSymbol()!=Symbol() || OrderMagicNumber()!=InpMagic) continue;
      if(OrderCloseTime()>=dayStart) count++;
   }
   for(int j=OrdersTotal()-1;j>=0;j--)
   {
      if(!OrderSelect(j,SELECT_BY_POS,MODE_TRADES)) continue;
      if(OrderSymbol()!=Symbol() || OrderMagicNumber()!=InpMagic) continue;
      if(OrderOpenTime()>=dayStart) count++;
   }
   return count;
}

double TodayNetProfit()
{
   double net=0.0;
   datetime dayStart=StrToTime(TimeToString(TimeCurrent(),TIME_DATE));
   for(int i=OrdersHistoryTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_HISTORY)) continue;
      if(OrderSymbol()!=Symbol() || OrderMagicNumber()!=InpMagic) continue;
      if(OrderCloseTime()>=dayStart) net+=OrderProfit()+OrderSwap()+OrderCommission();
   }
   for(int j=OrdersTotal()-1;j>=0;j--)
   {
      if(!OrderSelect(j,SELECT_BY_POS,MODE_TRADES)) continue;
      if(OrderSymbol()!=Symbol() || OrderMagicNumber()!=InpMagic) continue;
      net+=OrderProfit()+OrderSwap()+OrderCommission();
   }
   return net;
}

int CountOpenTrades()
{
   int count=0;
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      if(OrderSymbol()==Symbol() && OrderMagicNumber()==InpMagic && (OrderType()==OP_BUY || OrderType()==OP_SELL)) count++;
   }
   return count;
}

double NormalizeLotsDown(double lots)
{
   double minLot=MarketInfo(Symbol(),MODE_MINLOT);
   double maxLot=MarketInfo(Symbol(),MODE_MAXLOT);
   double step=MarketInfo(Symbol(),MODE_LOTSTEP);
   if(step<=0) step=0.01;
   if(lots>maxLot) lots=maxLot;
   lots=MathFloor(lots/step+1e-8)*step;
   int lotDigits=2;
   if(step>=1.0) lotDigits=0; else if(step>=0.1) lotDigits=1; else if(step<0.01) lotDigits=3;
   lots=NormalizeDouble(lots,lotDigits);
   if(lots<minLot) return 0.0;
   return lots;
}

double CalculateLotsForRisk(double riskUSD,double stopDistancePrice)
{
   double tickValue=MarketInfo(Symbol(),MODE_TICKVALUE);
   double tickSizeRaw=MarketInfo(Symbol(),MODE_TICKSIZE);
   double minLot=MarketInfo(Symbol(),MODE_MINLOT);
   double maxLot=MarketInfo(Symbol(),MODE_MAXLOT);
   double lotStep=MarketInfo(Symbol(),MODE_LOTSTEP);

   if(tickValue<=0 || tickSizeRaw<=0 || Point<=0 || stopDistancePrice<=0 ||
      minLot<=0 || maxLot<minLot || lotStep<=0)
   {
      Print("LOT SPEC ERROR | tickValue=",DoubleToString(tickValue,8),
            " tickSizeRaw=",DoubleToString(tickSizeRaw,10),
            " Point=",DoubleToString(Point,Digits+2),
            " minLot=",DoubleToString(minLot,4),
            " maxLot=",DoubleToString(maxLot,4),
            " lotStep=",DoubleToString(lotStep,4),
            " stopDistance=",DoubleToString(stopDistancePrice,Digits+2));
      return 0.0;
   }

   // Broker feeds differ: MODE_TICKSIZE is commonly reported in points,
   // but some feeds return the tick size directly in price units. Normalize both.
   double tickSizePrice=tickSizeRaw;
   if(tickSizeRaw>=Point*10.0) tickSizePrice=tickSizeRaw*Point;
   if(tickSizePrice<=0)
   {
      Print("LOT SPEC ERROR | normalized tick size is invalid. raw=",DoubleToString(tickSizeRaw,10));
      return 0.0;
   }

   double ticksToStop=stopDistancePrice/tickSizePrice;
   double riskPerLot=ticksToStop*tickValue;
   double rawLots=riskUSD/riskPerLot;
   double minLotRisk=minLot*riskPerLot;

   Print("LOT CALC | riskBudgetUSD=",DoubleToString(riskUSD,2),
         " stopDistance=",DoubleToString(stopDistancePrice,Digits+2),
         " tickValue=",DoubleToString(tickValue,8),
         " tickSizeRaw=",DoubleToString(tickSizeRaw,10),
         " tickSizePrice=",DoubleToString(tickSizePrice,10),
         " riskPerLotUSD=",DoubleToString(riskPerLot,4),
         " rawLots=",DoubleToString(rawLots,6),
         " minLot=",DoubleToString(minLot,4),
         " minLotRiskUSD=",DoubleToString(minLotRisk,4),
         " lotStep=",DoubleToString(lotStep,4));

   // Never round up to broker minimum if that would exceed the risk budget.
   if(rawLots<minLot)
   {
      Print("LOT BLOCKED | broker minimum lot would risk USD ",DoubleToString(minLotRisk,2),
            ", above allowed USD ",DoubleToString(riskUSD,2),". Risk limit preserved.");
      return 0.0;
   }
   double lots=NormalizeLotsDown(rawLots);
   if(lots<minLot || lots>maxLot) return 0.0;
   return lots;
}

bool TradeGate(string &reason)
{
   reason="OK";
   UpdateRiskGovernor();
   if(g_governorState==4) { reason="campaign loss limit reached (-$50); governor latched until manual reset token changes"; return false; }
   if(InpBlockOnAccountTypeMismatch && AccountTypeMismatch()) { reason="account type mismatch: terminal IsDemo() contradicts user-confirmed account report; verify broker account before trading"; return false; }
   if(InpMode!=AUTO_EXECUTION) { reason="OBSERVE_ONLY mode"; return false; }
   if(!IsTradeAllowed()) { reason="terminal or EA trading not allowed"; return false; }
   if(AccountCurrency()!="USD") { reason="account currency is not USD; cannot verify USD risk budget safely"; return false; }
   if(EffectiveOperatingCapitalUSD()<=0.0) { reason="insufficient positive account equity for operating capital"; return false; }
   if(MarketInfo(Symbol(),MODE_SPREAD)>InpMaxSpreadPoints) { reason="spread gate"; return false; }
   if(CountOpenTrades()>=InpMaxOpenTrades) { reason="maximum open trades reached"; return false; }
   if(CountTodayTrades()>=InpMaxTradesPerDay) { reason="daily trade count limit"; return false; }
   if(TodayNetProfit()<=-EffectiveDailyLossLimitUSD()) { reason="daily loss limit reached"; return false; }
   if(IsTradeContextBusy()) { reason="trade context busy"; return false; }
   return true;
}

bool SendOrder(int direction)
{
   string gateReason="";
   if(!TradeGate(gateReason))
   {
      Print("ORDER BLOCKED | ",gateReason);
      return false;
   }
   RefreshRates();
   double atr=GetATR(1);
   if(atr<=0) { Print("ORDER BLOCKED | invalid ATR"); return false; }
   double stopDistance=atr*InpStopATR;
   double targetDistance=atr*InpTargetATR;
   double riskUSD=EffectiveRiskBudgetUSD();
   if(riskUSD<=0) { Print("ORDER BLOCKED | calculated risk is zero"); return false; }
   double lots=CalculateLotsForRisk(riskUSD,stopDistance);
   if(lots<=0) { Print("ORDER BLOCKED | lot calculation failed; inspect preceding LOT CALC / LOT SPEC diagnostics"); return false; }

   int type=(direction>0?OP_BUY:OP_SELL);
   double price=(direction>0?Ask:Bid);
   double sl=(direction>0?price-stopDistance:price+stopDistance);
   double tp=(direction>0?price+targetDistance:price-targetDistance);
   int stopLevel=(int)MarketInfo(Symbol(),MODE_STOPLEVEL);
   double minStop=stopLevel*Point;
   if(MathAbs(price-sl)<minStop || MathAbs(tp-price)<minStop)
   {
      Print("ORDER BLOCKED | broker stop-level constraint");
      return false;
   }
   price=NormalizeDouble(price,Digits); sl=NormalizeDouble(sl,Digits); tp=NormalizeDouble(tp,Digits);
   ResetLastError();
   int ticket=OrderSend(Symbol(),type,lots,price,InpSlippagePoints,sl,tp,"Bitey SBT v1.43 auto",InpMagic,0,clrNONE);
   if(ticket<0)
   {
      Print("ORDER ERROR | code=",GetLastError()," lots=",DoubleToString(lots,2)," riskUSD=",DoubleToString(riskUSD,2));
      return false;
   }
   double tickValue=MarketInfo(Symbol(),MODE_TICKVALUE);
   double tickSizeRaw=MarketInfo(Symbol(),MODE_TICKSIZE);
   double tickSizePrice=tickSizeRaw;
   if(tickSizeRaw>=Point*10.0) tickSizePrice=tickSizeRaw*Point;
   double actualRiskUSD=(tickValue>0 && tickSizePrice>0 ? lots*(stopDistance/tickSizePrice)*tickValue : riskUSD);
   StoreEntryExperience(ticket,direction,actualRiskUSD);
   Print("ORDER OPENED | ticket=",ticket," direction=",(direction>0?"BUY":"SELL"),
         " lots=",DoubleToString(lots,2)," riskUSD<=",DoubleToString(riskUSD,2),
         " SL=",DoubleToString(sl,Digits)," TP=",DoubleToString(tp,Digits));
   return true;
}

void PrintEvidence(string modelName,string direction,DirectionEvidence &e,int signal)
{
   Print(modelName," ",direction," n=",e.samples," wr=",DoubleToString(e.winRate,2),
         " avgR=",DoubleToString(e.avgR,2)," pass=",(EvidencePass(e)?"YES":"NO")," signal=",signal);
}

void EvaluateEngine()
{
   int trend=0,momentum=0,donchian=0,meanrev=0,pullback=0;
   if(!GetModelSignals(1,trend,momentum,donchian,meanrev,pullback))
   {
      Print("DATA_GATE: insufficient history or indicator data.");
      return;
   }

   double close1=iClose(Symbol(),Period(),1);
   double emaFast1=iMA(Symbol(),Period(),InpFastEMA,0,MODE_EMA,PRICE_CLOSE,1);
   double emaSlow1=iMA(Symbol(),Period(),InpSlowEMA,0,MODE_EMA,PRICE_CLOSE,1);
   double emaTrend1=iMA(Symbol(),Period(),InpTrendEMA,0,MODE_EMA,PRICE_CLOSE,1);
   double rsi1=iRSI(Symbol(),Period(),InpRSIPeriod,PRICE_CLOSE,1);
   double adx1=iADX(Symbol(),Period(),InpADXPeriod,PRICE_CLOSE,MODE_MAIN,1);
   double plusDI1=iADX(Symbol(),Period(),InpADXPeriod,PRICE_CLOSE,MODE_PLUSDI,1);
   double minusDI1=iADX(Symbol(),Period(),InpADXPeriod,PRICE_CLOSE,MODE_MINUSDI,1);
   double atr1=GetATR(1);
   if(InpPrintDiagnostics)
      Print("BITEY DIAGNOSTIC | close=",DoubleToString(close1,Digits),
            " EMAfast=",DoubleToString(emaFast1,Digits)," EMAslow=",DoubleToString(emaSlow1,Digits),
            " EMAtrend=",DoubleToString(emaTrend1,Digits)," RSI=",DoubleToString(rsi1,2),
            " ADX=",DoubleToString(adx1,2)," +DI=",DoubleToString(plusDI1,2),
            " -DI=",DoubleToString(minusDI1,2)," ATR=",DoubleToString(atr1,Digits),
            " signals T=",trend," M=",momentum," D=",donchian," R=",meanrev," P=",pullback,
            " spreadPts=",(int)MarketInfo(Symbol(),MODE_SPREAD));

   DirectionEvidence buy[5],sell[5];
   bool buyPass0=false,buyPass1=false,buyPass2=false,buyPass3=false,buyPass4=false;
   bool sellPass0=false,sellPass1=false,sellPass2=false,sellPass3=false,sellPass4=false;
   double buyAvgR0=0.0,buyAvgR1=0.0,buyAvgR2=0.0,buyAvgR3=0.0,buyAvgR4=0.0;
   double sellAvgR0=0.0,sellAvgR1=0.0,sellAvgR2=0.0,sellAvgR3=0.0,sellAvgR4=0.0;
   int signals[5];
   signals[0]=trend; signals[1]=momentum; signals[2]=donchian; signals[3]=meanrev; signals[4]=pullback;
   for(int initIndex=0;initIndex<5;initIndex++)
   {
      ResetEvidence(buy[initIndex]);
      ResetEvidence(sell[initIndex]);
   }

   int buyVotes=0,sellVotes=0;
   // Build telemetry JSON while each evidence record is freshly computed.
   // Avoid a later dynamic-index read of the structure arrays, which triggers
   // conservative "possible use of uninitialized variable" warnings in MQL4.
   string modelsJson="[";
   for(int m=0;m<5;m++)
   {
      BuildEvidence(m,1,buy[m]);
      BuildEvidence(m,-1,sell[m]);
      bool thisBuyPass=EvidencePass(buy[m]);
      bool thisSellPass=EvidencePass(sell[m]);
      double thisBuyAvgR=buy[m].avgR;
      double thisSellAvgR=sell[m].avgR;
      if(m==0) { buyPass0=thisBuyPass; sellPass0=thisSellPass; buyAvgR0=thisBuyAvgR; sellAvgR0=thisSellAvgR; }
      else if(m==1) { buyPass1=thisBuyPass; sellPass1=thisSellPass; buyAvgR1=thisBuyAvgR; sellAvgR1=thisSellAvgR; }
      else if(m==2) { buyPass2=thisBuyPass; sellPass2=thisSellPass; buyAvgR2=thisBuyAvgR; sellAvgR2=thisSellAvgR; }
      else if(m==3) { buyPass3=thisBuyPass; sellPass3=thisSellPass; buyAvgR3=thisBuyAvgR; sellAvgR3=thisSellAvgR; }
      else if(m==4) { buyPass4=thisBuyPass; sellPass4=thisSellPass; buyAvgR4=thisBuyAvgR; sellAvgR4=thisSellAvgR; }
      if(signals[m]>0 && thisBuyPass) buyVotes++;
      if(signals[m]<0 && thisSellPass) sellVotes++;
      if(InpPrintDiagnostics)
      {
         PrintEvidence(g_modelNames[m],"BUY",buy[m],(signals[m]>0?1:0));
         PrintEvidence(g_modelNames[m],"SELL",sell[m],(signals[m]<0?-1:0));
      }
      WriteEvidenceRow(g_modelNames[m],"BUY",buy[m],(signals[m]>0?1:0),"EVIDENCE");
      WriteEvidenceRow(g_modelNames[m],"SELL",sell[m],(signals[m]<0?-1:0),"EVIDENCE");

      if(m>0) modelsJson+=",";
      modelsJson+="{\"name\":\""+g_modelNames[m]+"\",\"signal\":"+IntegerToString(signals[m])+",";
      modelsJson+="\"buy\":"+EvidenceToJson(buy[m])+",";
      modelsJson+="\"sell\":"+EvidenceToJson(sell[m])+"}";
   }
   modelsJson+="]";

   UpdateRiskGovernor();
   if(g_governorState==4)
   {
      Print("RISK GOVERNOR LOCK | campaignNetUSD=",DoubleToString(g_campaignNetUSD,2)," | new entries disabled; open positions remain managed by SL/TP/time exit.");
   }
   int requiredVotes=RequiredModelVotes();
   int decision=0;
   string decisionText="WAIT: insufficient evidence or conflicting directions";
   if(g_governorState==4) decisionText="BLOCKED: campaign loss limit reached";
   else if(buyVotes>=requiredVotes && sellVotes==0) { decision=1; decisionText="BUY candidate"; }
   else if(sellVotes>=requiredVotes && buyVotes==0) { decision=-1; decisionText="SELL candidate"; }
   else if(buyVotes>0 && sellVotes>0) decisionText="WAIT: conflicting model votes";

   Print("BITEY SBT v1.43 | governor=",GovernorStateName(g_governorState)," campaignNetUSD=",DoubleToString(g_campaignNetUSD,2)," requiredVotes=",requiredVotes," | ",Symbol()," TF=",Period()," BUY votes=",buyVotes," SELL votes=",sellVotes,
         " | TREND signal=",trend," MOMENTUM signal=",momentum," DONCHIAN signal=",donchian," MEANREV signal=",meanrev," PULLBACK signal=",pullback,
         " | DECISION=",decisionText);

   string bestStrategy="NONE";
   double bestScore=0.0;
   if(decision>0)
   {
      if(trend>0 && buyPass0) { bestStrategy=g_modelNames[0]; bestScore=buyAvgR0; }
      else if(momentum>0 && buyPass1) { bestStrategy=g_modelNames[1]; bestScore=buyAvgR1; }
      else if(donchian>0 && buyPass2) { bestStrategy=g_modelNames[2]; bestScore=buyAvgR2; }
      else if(meanrev>0 && buyPass3) { bestStrategy=g_modelNames[3]; bestScore=buyAvgR3; }
      else if(pullback>0 && buyPass4) { bestStrategy=g_modelNames[4]; bestScore=buyAvgR4; }
   }
   else if(decision<0)
   {
      if(trend<0 && sellPass0) { bestStrategy=g_modelNames[0]; bestScore=sellAvgR0; }
      else if(momentum<0 && sellPass1) { bestStrategy=g_modelNames[1]; bestScore=sellAvgR1; }
      else if(donchian<0 && sellPass2) { bestStrategy=g_modelNames[2]; bestScore=sellAvgR2; }
      else if(meanrev<0 && sellPass3) { bestStrategy=g_modelNames[3]; bestScore=sellAvgR3; }
      else if(pullback<0 && sellPass4) { bestStrategy=g_modelNames[4]; bestScore=sellAvgR4; }
   }

   string gateReason="";
   if(decision==0)
   {
      gateReason=(g_governorState==4?"CAMPAIGN_LOSS_LIMIT_LOCKED":"NO_QUALIFIED_DIRECTIONAL_SETUP");
      Print("NO ENTRY | reason=NO_QUALIFIED_DIRECTIONAL_SETUP; signals T/M/D/R/P=",
            trend,"/",momentum,"/",donchian,"/",meanrev,"/",pullback,
            "; votes BUY/SELL=",buyVotes,"/",sellVotes,
            ". No trade is forced; wait for a confirmed setup with historical evidence.");
      SendSbtSnapshot(decision,decisionText,buyVotes,sellVotes,trend,momentum,donchian,meanrev,pullback,
                      modelsJson,bestStrategy,bestScore,close1,emaFast1,emaSlow1,emaTrend1,rsi1,adx1,atr1,
                      false,gateReason,"NO_ENTRY");
      return;
   }
   if(!TradeGate(gateReason))
   {
      Print("DECISION NOT EXECUTED | ",decisionText," | gate=",gateReason);
      SendSbtSnapshot(decision,decisionText,buyVotes,sellVotes,trend,momentum,donchian,meanrev,pullback,
                      modelsJson,bestStrategy,bestScore,close1,emaFast1,emaSlow1,emaTrend1,rsi1,adx1,atr1,
                      false,gateReason,"BLOCKED_BY_RISK_GATE");
      return;
   }
   g_currentBestStrategy=bestStrategy;
   g_currentStateId=BuildStateId(close1,emaFast1,emaSlow1,emaTrend1,rsi1,adx1,atr1);
   g_currentRiskBudgetUSD=EffectiveRiskBudgetUSD();
   bool orderOpened=SendOrder(decision);
   SendSbtSnapshot(decision,decisionText,buyVotes,sellVotes,trend,momentum,donchian,meanrev,pullback,
                   modelsJson,bestStrategy,bestScore,close1,emaFast1,emaSlow1,emaTrend1,rsi1,adx1,atr1,
                   true,"OK",orderOpened?"ORDER_OPENED":"ORDER_SEND_FAILED");
}
