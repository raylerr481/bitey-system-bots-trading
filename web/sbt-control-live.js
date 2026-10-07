(() => {
  'use strict';
  const API=(window.SBT_API_URL||'https://bitey-system-bots-trading-api.onrender.com').replace(/\/$/,'');
  const esc=v=>String(v??'—').replace(/[&<>"]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c]));
  const api=async(path,options={})=>{const r=await fetch(API+path,{cache:'no-store',...options,headers:{'Content-Type':'application/json',...(options.headers||{})}});if(!r.ok)throw Error('HTTP '+r.status);return r.json();};
  const box=(id,title,html)=>{
    let e=document.getElementById(id);
    if(!e){e=document.createElement('div');e.id=id;e.className='card';e.style.marginBottom='12px';}
    e.innerHTML='<h3>'+title+'</h3>'+html;
    return e;
  };
  const place=(page,id,html)=>{const p=document.getElementById(page);if(!p)return;const e=box(id,'',html);const hero=p.querySelector('.hero');if(hero&&e.parentNode!==p)p.insertBefore(e,hero.nextSibling);};
  const kv=(obj)=>Object.entries(obj).map(([k,v])=>'<div class="risk"><span>'+esc(k)+'</span><b>'+esc(v)+'</b></div>').join('');

  async function loadMt4Parameters(){
    try{
      const d=await api('/api/v1/mt4/bitey-latest'),r=d.report||{};
      const risk=r.risk||{},a=r.account||{},b=r.bot||{},s=r.state||{},m=r.metrics||{};
      const rows={
        'EA':b.name||r.source||'—','Magic':b.magic??'—','Symbol':r.symbol||'—',
        'Strategy':r.strategy||b.strategy||'—','Strategy TF':r.timeframe||r.strategy_timeframe||'—',
        'Chart TF':r.chart_timeframe||'—','Signal':r.signal||m.signal||s.current||'NONE',
        'Execution':r.execution_enabled?'ENABLED':'BLOCKED','Research only':r.research_only?'YES':'NO',
        'SBT telemetry':r.sbt_enabled===false?'DISABLED':'ENABLED',
        'Operating environment':'MT4 DEMO / TRADER WILL',
        'MT4 reported mode':r.mode||a.reported_mode||'UNKNOWN',
        'Operational capital': '$'+Number(risk.operational_capital_usd||500).toFixed(2),
        'Risk / trade': (risk.risk_pct??'—')+'%',
        'Risk budget': '$'+Number(risk.risk_budget_usd||0).toFixed(2),
        'Max daily loss': (risk.max_daily_loss_pct??'—')+'%',
        'Daily loss': '$'+Number(risk.daily_loss_usd||0).toFixed(2),
        'Max spread': risk.max_spread_points??'—',
        'Max trades/day': risk.max_trades_day??'—',
        'Max open trades': risk.max_open_trades??'—',
        'Positions': a.position_count??m.positions_open??s.position_count??0,
        'Spread': s.spread_points??m.spread_points??'—',
        'Daily DD': (s.daily_drawdown_pct??m.daily_drawdown_pct??'—')+'%',
        'Trades today': s.trades_today??m.trades_today??0
      };
      const html='<div class="test-grid">'+Object.entries(rows).map(([k,v])=>'<div class="kpi"><div class="label">'+esc(k)+'</div><div class="v">'+esc(v)+'</div></div>').join('')+'</div><div class="notice">Fuente: snapshot real recibido desde MT4 Evidence Lab. SBT no inventa ni modifica parámetros; Risk Gate conserva la autoridad.</div>';
      ['dashboard','turtle','ai-bot-lab','validation','risk'].forEach(p=>place(p,'mt4ParameterSnapshot',html));
    }catch(e){
      ['dashboard','turtle','ai-bot-lab','validation','risk'].forEach(p=>place(p,'mt4ParameterSnapshot','<div class="notice">MT4/SBT todavía no entregó un snapshot utilizable.</div>'));
    }
  }

  async function loadQLearning(){
    try{
      const d=await fetch('https://bitey-ia-suprabrain.onrender.com/api/v1/q-learning/status',{cache:'no-store'}).then(r=>{if(!r.ok)throw Error(r.status);return r.json();});
      const s=d.status||d;
      const html='<div class="test-grid">'+[
        ['Algorithm',s.algorithm||'q-routing-v1'],['Enabled',s.enabled?'YES':'NO'],['States',s.states??0],
        ['Learned pairs',s.learned_pairs??0],['Transitions',s.transitions??0],['Persistence',s.persistence||'—']
      ].map(x=>'<div class="kpi"><div class="label">'+esc(x[0])+'</div><div class="v">'+esc(x[1])+'</div></div>').join('')+'</div><div class="notice">Q-learning es solo aprendizaje/asesoría. Risk Gate sigue siendo autoritativo y el capital operativo permanece limitado a $500.</div>';
      place('dashboard','qLearningLive',html);
      place('ai-bot-lab','qLearningLive',html);
      place('evolution','qLearningLive',html);
    }catch(e){
      place('dashboard','qLearningLive','<div class="notice">Q-learning de Bitey IA no disponible en este momento.</div>');
    }
  }

  async function loadPageData(id){
    try{
      if(id==='models'){
        const d=await api('/api/v1/ai/providers');
        place(id,'modelsLive','<div class="test-grid">'+(d.providers||[]).map(x=>'<div class="kpi"><div class="label">'+esc(x.name)+'</div><div class="v">'+esc(x.id)+'</div><div class="small">'+esc((x.connection_modes||[]).join(' · '))+'</div></div>').join('')+'</div><div class="notice">Gemini API permanece excluido por política del proyecto. No se realizan llamadas pagadas automáticamente.</div>');
      }
      if(id==='connections'){
        const [p,ai,per]=await Promise.all([api('/api/v1/integrations/platforms'),api('/api/v1/integrations/ai'),api('/api/v1/integrations/permissions')]);
        place(id,'connectionsLive','<div class="test-grid">'+(p.platforms||[]).map(x=>'<div class="kpi"><div class="label">'+esc(x.name)+'</div><div class="v">'+esc((x.modes||[]).join(' · '))+'</div><div class="small">'+esc((x.transport||[]).join(' · '))+'</div></div>').join('')+'</div><div class="notice">AI adapters: '+esc((ai.providers||ai.adapters||[]).map(x=>x.name||x.id||x).join(' · '))+'<br>Permisos disponibles: '+esc((per.permissions||[]).map(x=>x.label||x.id).join(' · '))+'</div>');
      }
      if(id==='bots'){
        const d=await api('/api/v1/bot-builder/catalog');
        place(id,'botsLive','<div class="test-grid">'+(d.steps||[]).map(x=>'<div class="kpi"><div class="label">Pipeline</div><div class="v">'+esc(x)+'</div></div>').join('')+'</div><div class="notice">Live: '+esc(d.live)+' · Real money: '+esc(d.real_money)+' · Broker orders: '+esc(d.broker_orders)+'</div>');
      }
      if(id==='risk'){
        const [p,t,g]=await Promise.all([api('/api/v1/guardian/policy'),api('/api/v1/turtle/status'),api('/api/v1/mt4/bitey-latest')]);
        const r=g.report||{},a=r.account||{},risk=r.risk||{};
        place(id,'riskLive','<div class="test-grid">'+[
          ['Risk Gate','AUTHORITATIVE'],['MT4 environment','MT4 DEMO / TRADER WILL'],
          ['Operational cap','$'+Number(risk.operational_capital_usd||500).toFixed(2)],
          ['Risk/trade',(risk.risk_pct??'—')+'%'],['Daily max',(risk.max_daily_loss_pct??'—')+'%'],
          ['Guardian',p.risk_increase_allowed===false?'NO RISK INCREASE':'CHECK']
        ].map(x=>'<div class="kpi"><div class="label">'+esc(x[0])+'</div><div class="v">'+esc(x[1])+'</div></div>').join('')+'</div><div class="notice">'+esc(p.note||'')+'<br>Turtle state: '+esc(t.next_action||t.state?.next_action||'—')+'</div>');
      }
      if(id==='setup'){
        const d=await api('/api/v1/system');
        place(id,'setupLive','<div class="notice">Backend: '+esc(d.module)+' · Live trading: '+esc(d.live_trading_enabled)+' · Real money: '+esc(d.real_money_enabled)+' · MT4 telemetry: '+(d.capabilities||[]).includes('mt4-telemetry')+'</div>');
      }
      if(id==='research'){
        const d=await api('/api/v1/experiments?limit=10');
        place(id,'researchLive','<div class="notice">Experimentos registrados: '+esc(d.count??0)+'<br>Selecciona/crea un experimento para vincular MT4 → evidencia → validación.</div>');
      }
      if(id==='validation'){
        const d=await api('/api/v1/validation/virtual');
        place(id,'validationLive','<div class="notice">Validación virtual backend: '+esc(d.validation?.status||d.status||'COMPLETED')+' · Trades: '+esc(d.closed_trades??d.trades??'—')+' · DD: '+esc(d.max_drawdown_pct??'—')+'%</div>');
      }
    }catch(e){
      place(id,id+'Live','<div class="notice">Backend no disponible para este módulo. No se muestran datos inventados.</div>');
    }
  }

  async function createRealExperiment(){
    const id='ENSEMBLE-M15-'+new Date().toISOString().replace(/[-:.TZ]/g,'').slice(0,14);
    try{
      const r=await api('/api/v1/experiments',{method:'POST',body:JSON.stringify({
        experiment_id:id,symbol:'EURUSD',strategy:'ENSEMBLE',strategy_timeframe:'M15',chart_timeframe:'H1',
        hypothesis:{source:'SBT Research Lab',objective:'maximize_monthly_profit_subject_to_risk'},
        feature_candidates:[],metadata:{created_from:'web',mt4_status:'WAITING_FOR_MT4'}
      })});
      localStorage.setItem('sbt_current_experiment_id',id);
      window.dispatchEvent(new CustomEvent('sbt:experiment-selected',{detail:{experiment_id:id}}));
      const e=document.getElementById('researchResult');if(e){e.style.display='block';e.innerHTML='<strong>Experimento creado en backend.</strong><br>ID: '+esc(id)+'<br>Persistido: '+esc(r.persisted)+'<br>MT4 permanece bajo control manual.';}
      loadPageData('research');
    }catch(e){const x=document.getElementById('researchResult');if(x){x.style.display='block';x.textContent='No fue posible crear el experimento en SBT.';}}
  }

  function patchHandlers(){
    const create=document.getElementById('createExperiment');if(create){create.onclick=createRealExperiment;}
    const build=document.getElementById('buildPlan');if(build){build.onclick=async()=>{
      try{
        const state={ai_provider:document.querySelector('#aiChoices .selected')?.dataset.ai||'bitey',ai_connection:'api',platform:document.querySelector('#platformChoices .selected')?.dataset.platform==='mt4'?'mt4':'bitey-sbt-native',mode:'demo',permissions:[...document.querySelectorAll('#permissionChoices button.selected')].map(x=>x.dataset.permission==='demo_execution'?'demo_execute':x.dataset.permission).filter(Boolean),automation:!!document.getElementById('automation')?.checked};
        const d=await api('/api/v1/integrations/plan',{method:'POST',body:JSON.stringify(state)});
        const e=document.getElementById('planResult');if(e){e.style.display='block';e.innerHTML='<strong>Plan validado por SBT.</strong><br>Estado: '+esc(d.stage)+' · Permitido: '+esc(d.allowed)+'<br>Risk Gate: '+esc(d.plan?.risk_gate||'mandatory');}
      }catch(e){const x=document.getElementById('planResult');if(x){x.style.display='block';x.textContent='No fue posible validar el plan con SBT.';}}
    };}
    const convert=document.querySelector('[id="convertExperiment"],#marketConvertExperiment');if(convert)convert.onclick=createRealExperiment;
  }

  function boot(){
    patchHandlers();
    loadMt4Parameters();
    loadQLearning();
    document.querySelectorAll('[data-page]').forEach(b=>b.addEventListener('click',()=>setTimeout(()=>loadPageData(b.dataset.page),80)));
    ['dashboard','turtle','ai-bot-lab','validation','risk'].forEach(x=>loadPageData(x));
    setInterval(loadMt4Parameters,5000);
    setInterval(loadQLearning,15000);
  }
  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',boot,{once:true});else boot();
})();