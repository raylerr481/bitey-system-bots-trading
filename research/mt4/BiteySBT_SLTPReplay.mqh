#ifndef __BITEY_SBT_SLTP_REPLAY_MQH__
#define __BITEY_SBT_SLTP_REPLAY_MQH__

// Research-only OHLC replay helper. It does not send or modify orders.
// Include into an EA that defines ModelSignal(model, shift).
// Conservative rule: if SL and TP are both touched within one OHLC bar,
// count SL first because OHLC cannot establish which level was reached first.
// Spread is modeled in price units; commission, swap, slippage and gaps remain
// separate cost inputs/limitations and must be added before trusting results.

struct SBT99ReplayStats
{
   int trades;
   int wins;
   int losses;
   int ambiguousBars;
   double winRate;
   double netR;
   double avgR;
   double grossWinR;
   double grossLossR;
   double profitFactor;
   double maxDrawdownR;
   bool sufficient;
};

int ModelSignal(int model, int s);

void SBT99_ReplaySLTP(int model,
                                  int side,
                                  int lookbackBars,
                                  int horizonBars,
                                  int atrPeriod,
                                  double stopATR,
                                  double targetATR,
                                  double spreadPoints,
                                  SBT99ReplayStats &r)
{
   r.trades=0; r.wins=0; r.losses=0; r.ambiguousBars=0;
   r.winRate=0.0; r.netR=0.0; r.avgR=0.0;
   r.grossWinR=0.0; r.grossLossR=0.0; r.profitFactor=0.0; r.maxDrawdownR=0.0; r.sufficient=false;

   if((side!=1 && side!=-1) || lookbackBars<1 || horizonBars<1 ||
      atrPeriod<2 || stopATR<=0.0 || targetATR<=0.0 || Bars<horizonBars+atrPeriod+10)
      return;

   int maxSignalShift=MathMin(lookbackBars, Bars-horizonBars-atrPeriod-3);
   int nextAllowedSignalShift=2147483647;
   double equityR=0.0, peakR=0.0;
   // Iterate from older bars to newer bars so results are deterministic.
   for(int sigShift=maxSignalShift; sigShift>=horizonBars+2; sigShift--)
   {
      if(sigShift>nextAllowedSignalShift) continue;
      if(ModelSignal(model,sigShift)!=side) continue;

      double atr=iATR(Symbol(),Period(),atrPeriod,sigShift);
      if(atr<=Point) continue;

      // Signal known only after the signal candle closes. Enter at next candle open.
      int entryShift=sigShift-1;
      double entry=iOpen(Symbol(),Period(),entryShift);
      if(entry<=0.0) continue;

      double spread=spreadPoints*Point;
      // Conservative simple spread treatment: charge a full spread against the trade.
      double entryPrice=(side==1 ? entry+spread : entry);
      double stopDistance=atr*stopATR;
      double targetDistance=atr*targetATR;
      double sl=(side==1 ? entryPrice-stopDistance : entryPrice+stopDistance);
      double tp=(side==1 ? entryPrice+targetDistance : entryPrice-targetDistance);
      double resultR=0.0;
      bool finished=false;

      // Scan forward in chronological order, including entry candle.
      int lastShift=MathMax(0,entryShift-horizonBars+1);
      for(int barShift=entryShift; barShift>=lastShift; barShift--)
      {
         double hi=iHigh(Symbol(),Period(),barShift);
         double lo=iLow(Symbol(),Period(),barShift);
         bool hitSL=(side==1 ? lo<=sl : (hi+spread)>=sl);
         bool hitTP=(side==1 ? hi>=tp : (lo+spread)<=tp);

         double barOpen=iOpen(Symbol(),Period(),barShift);
         if(hitSL && hitTP)
         {
            r.ambiguousBars++;
            // SL-first. Account for a gap through the stop at the bar open.
            if(side==1 && barOpen<sl) resultR=(entryPrice-barOpen)/stopDistance;
            else if(side==-1 && barOpen+spread>sl) resultR=(entryPrice-(barOpen+spread))/stopDistance;
            else resultR=-1.0;
            finished=true;
            break;
         }
         if(hitSL)
         {
            // A gap through the stop fills at the adverse open, not at the stop.
            if(side==1 && barOpen<sl) resultR=(entryPrice-barOpen)/stopDistance;
            else if(side==-1 && barOpen+spread>sl) resultR=(entryPrice-(barOpen+spread))/stopDistance;
            else resultR=-1.0;
            finished=true;
            break;
         }
         if(hitTP)
         {
            resultR=targetDistance/stopDistance;
            finished=true;
            break;
         }
      }

      if(!finished)
      {
         // Horizon exit at the last available close; spread was already charged at entry.
         double exitPrice=iClose(Symbol(),Period(),lastShift);
         if(exitPrice<=0.0) continue;
         // OHLC history is treated as BID data: a SELL exits at ASK (close + spread).
         if(side==-1) exitPrice+=spread;
         double move=(exitPrice-entryPrice)*side;
         resultR=move/stopDistance;
      }

      r.trades++;
      r.netR+=resultR;
      equityR+=resultR;
      if(equityR>peakR) peakR=equityR;
      double dd=peakR-equityR;
      if(dd>r.maxDrawdownR) r.maxDrawdownR=dd;
      nextAllowedSignalShift=lastShift-1; // avoid overlapping outcome windows for this model/side
      if(resultR>0.0)
      {
         r.wins++;
         r.grossWinR+=resultR;
      }
      else if(resultR<0.0)
      {
         r.losses++;
         r.grossLossR+=MathAbs(resultR);
      }
   }

   if(r.trades>0)
   {
      r.winRate=(double)r.wins/(double)r.trades;
      r.avgR=r.netR/(double)r.trades;
      if(r.grossLossR>0.0) r.profitFactor=r.grossWinR/r.grossLossR;
      else if(r.grossWinR>0.0) r.profitFactor=99.0;
   }
   r.sufficient=(r.trades>=12);
}
#endif
