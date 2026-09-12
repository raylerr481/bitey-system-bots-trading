(() => {
  const SUPABASE_URL = 'https://vttwfnnfcoavdhzeiqwl.supabase.co';
  const SUPABASE_KEY = 'sb_publishable_ewRqbdjRDJM8wmz-qdaPBA_tvj72lwK6';
  const LANGS = { es: 'Español', pt: 'Português', en: 'English' };
  const T = {
    es: { login:'Iniciar sesión', register:'Registrarse', email:'Correo electrónico', password:'Contraseña', enter:'Entrar', create:'Crear cuenta', verifyEmail:'Revisa tu correo para confirmar la cuenta.', forgot:'¿Olvidaste tu contraseña?', code:'Código de verificación', verify:'Verificar', twoFactor:'Verificación en dos pasos', enable2fa:'Activar 2FA', disable2fa:'Desactivar 2FA', scan:'Escanea este QR con tu app autenticadora y escribe el código de 6 dígitos.', language:'Idioma', account:'Mi cuenta', connected:'Cuenta conectada', logout:'Cerrar sesión', close:'Cerrar', setup2fa:'Configurar 2FA', enabled:'2FA activado correctamente.', disabled:'2FA desactivado.' },
    pt: { login:'Entrar', register:'Criar conta', email:'E-mail', password:'Senha', enter:'Entrar', create:'Criar conta', verifyEmail:'Verifique seu e-mail para confirmar a conta.', forgot:'Esqueceu sua senha?', code:'Código de verificação', verify:'Verificar', twoFactor:'Verificação em duas etapas', enable2fa:'Ativar 2FA', disable2fa:'Desativar 2FA', scan:'Escaneie este QR no seu aplicativo autenticador e digite o código de 6 dígitos.', language:'Idioma', account:'Minha conta', connected:'Conta conectada', logout:'Sair', close:'Fechar', setup2fa:'Configurar 2FA', enabled:'2FA ativado com sucesso.', disabled:'2FA desativado.' },
    en: { login:'Sign in', register:'Register', email:'Email', password:'Password', enter:'Sign in', create:'Create account', verifyEmail:'Check your email to confirm the account.', forgot:'Forgot your password?', code:'Verification code', verify:'Verify', twoFactor:'Two-step verification', enable2fa:'Enable 2FA', disable2fa:'Disable 2FA', scan:'Scan this QR with your authenticator app and enter the 6-digit code.', language:'Language', account:'My account', connected:'Account connected', logout:'Sign out', close:'Close', setup2fa:'Set up 2FA', enabled:'2FA enabled successfully.', disabled:'2FA disabled.' }
  };
  let supabase = null, session = null, factorId = null;
  let lang = localStorage.getItem('bitey-language') || (navigator.language || 'es').slice(0,2);
  if (!T[lang]) lang = 'es';
  const t = k => T[lang][k] || T.es[k] || k;
  const $ = s => document.querySelector(s);

  async function client() {
    if (supabase) return supabase;
    const mod = await import('https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/+esm');
    supabase = mod.createClient(SUPABASE_URL, SUPABASE_KEY, { auth:{ persistSession:true, autoRefreshToken:true, detectSessionInUrl:true } });
    return supabase;
  }
  function emitLanguage() { document.documentElement.lang = lang; localStorage.setItem('bitey-language', lang); window.dispatchEvent(new CustomEvent('bitey:language',{detail:{language:lang}})); render(); }
  function setLanguage(v) { if (T[v]) { lang=v; emitLanguage(); } }

  function style() {
    if ($('#bitey-auth-style')) return;
    const s=document.createElement('style'); s.id='bitey-auth-style'; s.textContent=`
      .bitey-auth-bar{display:flex;align-items:center;gap:8px;margin-left:auto}.bitey-auth-btn,.bitey-lang{border:1px solid #263444;background:#0a1017;color:#dce6ef;border-radius:9px;padding:8px 11px;font:600 12px system-ui}.bitey-auth-btn.primary{background:#52e6a2;color:#06100b;border-color:#52e6a2}.bitey-lang{cursor:pointer}.bitey-auth-overlay{position:fixed;inset:0;background:#000b;display:none;place-items:center;z-index:10000;padding:18px}.bitey-auth-overlay.open{display:grid}.bitey-auth-box{width:min(470px,100%);background:#0b1118;color:#edf3f8;border:1px solid #263444;border-radius:16px;padding:22px;box-shadow:0 25px 90px #000}.bitey-auth-box h2{margin:4px 0 8px}.bitey-auth-box p{color:#93a2b3;line-height:1.5}.bitey-auth-close{float:right;background:none;border:0;color:#93a2b3;font-size:22px}.bitey-auth-box label{display:grid;gap:6px;color:#aab7c5;font-size:12px;margin:11px 0}.bitey-auth-box input{width:100%;padding:10px;border-radius:9px;border:1px solid #263444;background:#070c12;color:#fff;outline:none}.bitey-auth-actions{display:flex;gap:8px;flex-wrap:wrap;margin-top:14px}.bitey-auth-actions button{border:1px solid #263444;background:#101821;color:#e5edf4;border-radius:9px;padding:9px 12px;cursor:pointer}.bitey-auth-actions .primary{background:#52e6a2;color:#06100b;border-color:#52e6a2;font-weight:800}.bitey-auth-status{min-height:20px;color:#aee8ca;font-size:12px}.bitey-auth-qr{display:block;max-width:210px;width:100%;margin:12px auto;background:#fff;border-radius:8px;padding:8px}.bitey-auth-meta{font-size:11px;color:#738294}.bitey-auth-bar .avatar{border-radius:50%;width:32px;height:32px;border:1px solid #2b3a4b;background:#101a24;color:#fff;font-weight:800}`; document.head.appendChild(s);
  }
  function modal() {
    if ($('#bitey-auth-overlay')) return;
    const o=document.createElement('div'); o.id='bitey-auth-overlay'; o.className='bitey-auth-overlay';
    o.innerHTML=`<section class="bitey-auth-box" role="dialog" aria-modal="true"><button class="bitey-auth-close" aria-label="${t('close')}">×</button><div class="eyebrow">BITEY SBT</div><h2 id="ba-title"></h2><p id="ba-sub"></p><div id="ba-body"></div></section>`;
    document.body.appendChild(o); $('.bitey-auth-close').onclick=()=>o.classList.remove('open');
  }
  function render() {
    style(); modal(); const title=$('#ba-title'), sub=$('#ba-sub'), body=$('#ba-body'); if(!title||!sub||!body)return;
    if(session){ title.textContent=t('account'); sub.textContent=session.user.email; body.innerHTML=`<p><b>${t('twoFactor')}</b></p><div id="ba-mfa"></div><div class="bitey-auth-actions"><button id="ba-logout">${t('logout')}</button></div>`; $('#ba-logout').onclick=async()=>{await supabase.auth.signOut();session=null;render();close();}; void renderMfa(); }
    else { title.textContent=t('login'); sub.textContent=t('account'); body.innerHTML=`<form id="ba-form"><label>${t('email')}<input id="ba-email" type="email" required autocomplete="email"></label><label>${t('password')}<input id="ba-password" type="password" required minlength="6" autocomplete="current-password"></label><div class="bitey-auth-actions"><button class="primary" id="ba-submit">${t('enter')}</button><button type="button" id="ba-register">${t('register')}</button></div></form><div class="bitey-auth-actions"><button id="ba-forgot">${t('forgot')}</button></div><p class="bitey-auth-status" id="ba-status"></p>`; $('#ba-form').onsubmit=e=>{e.preventDefault();void signIn(false)}; $('#ba-register').onclick=()=>register(); $('#ba-forgot').onclick=()=>resetPassword(); }
  }
  function open(){ render(); $('#bitey-auth-overlay').classList.add('open'); }
  function close(){ $('#bitey-auth-overlay')?.classList.remove('open'); }
  function bar(){
    if(document.querySelector('.bitey-auth-bar'))return; const top=document.querySelector('.top'); if(!top)return;
    const b=document.createElement('div'); b.className='bitey-auth-bar'; b.innerHTML=`<select class="bitey-lang" aria-label="${t('language')}">${Object.entries(LANGS).map(([k,v])=>`<option value="${k}" ${k===lang?'selected':''}>${v}</option>`).join('')}</select><button class="bitey-auth-btn primary" id="bitey-auth-open">${t('register')}</button>`; top.appendChild(b);
    b.querySelector('select').onchange=e=>setLanguage(e.target.value); $('#bitey-auth-open').onclick=open;
  }
  async function refresh(){ const c=await client(); const r=await c.auth.getSession(); session=r.data.session; c.auth.onAuthStateChange((_e,s)=>{session=s; renderBar();}); renderBar(); }
  function renderBar(){ const b=$('#bitey-auth-open'); if(!b)return; b.textContent=session?t('account'):t('register'); b.classList.toggle('primary',!session); }
  async function signIn(registerMode){
    const c=await client(), email=$('#ba-email')?.value.trim(), password=$('#ba-password')?.value; const status=$('#ba-status'); if(!email||!password)return; if(status)status.textContent='…';
    const r=registerMode?await c.auth.signUp({email,password,options:{emailRedirectTo:window.location.origin+window.location.pathname,data:{language:lang,product:'sbt'}}}):await c.auth.signInWithPassword({email,password});
    if(r.error){ if(status)status.textContent=r.error.message; return; }
    if(registerMode && !r.data.session){ if(status)status.textContent=t('verifyEmail'); return; }
    session=r.data.session; const factors=await c.auth.mfa.listFactors(); const verified=(factors.data?.totp||[]).find(f=>f.status==='verified'); if(verified){ const ch=await c.auth.mfa.challenge({factorId:verified.id}); return showChallenge(verified.id,ch.data?.id); }
    renderBar(); render();
  }
  async function register(){ render(); $('#ba-title').textContent=t('register'); $('#ba-sub').textContent=t('account'); $('#ba-body').innerHTML=`<form id="ba-form"><label>${t('email')}<input id="ba-email" type="email" required autocomplete="email"></label><label>${t('password')}<input id="ba-password" type="password" required minlength="6" autocomplete="new-password"></label><div class="bitey-auth-actions"><button class="primary" id="ba-submit">${t('create')}</button><button type="button" id="ba-back">${t('login')}</button></div></form><p class="bitey-auth-status" id="ba-status"></p>`; $('#ba-form').onsubmit=e=>{e.preventDefault();void signIn(true)}; $('#ba-back').onclick=render; }
  async function showChallenge(fid,cid){ const body=$('#ba-body'); if(!body)return; body.innerHTML=`<p><b>${t('twoFactor')}</b></p><p>${t('code')}</p><label><input id="ba-code" inputmode="numeric" autocomplete="one-time-code" maxlength="6"></label><div class="bitey-auth-actions"><button class="primary" id="ba-verify">${t('verify')}</button></div><p class="bitey-auth-status" id="ba-status"></p>`; $('#ba-verify').onclick=async()=>{const r=await supabase.auth.mfa.verify({factorId:fid,challengeId:cid,code:$('#ba-code').value.trim()}); if(r.error){$('#ba-status').textContent=r.error.message;return;} session=r.data.session; renderBar(); render();}; }
  async function resetPassword(){ const email=prompt(t('email')); if(!email)return; const r=await (await client()).auth.resetPasswordForEmail(email,{redirectTo:window.location.origin+window.location.pathname}); alert(r.error?r.error.message:'Password reset email sent.'); }
  async function renderMfa(){ const box=$('#ba-mfa'); if(!box)return; const c=await client(), r=await c.auth.mfa.listFactors(); const verified=(r.data?.totp||[]).find(f=>f.status==='verified'); if(verified){box.innerHTML=`<p class="bitey-auth-meta">${t('twoFactor')}: ✓</p><div class="bitey-auth-actions"><button id="ba-disable">${t('disable2fa')}</button></div>`; $('#ba-disable').onclick=async()=>{const x=await c.auth.mfa.unenroll({factorId:verified.id}); if(x.error){box.textContent=x.error.message;return;} render();}; return;}
    box.innerHTML=`<p>${t('twoFactor')}</p><div class="bitey-auth-actions"><button class="primary" id="ba-enable">${t('enable2fa')}</button></div>`; $('#ba-enable').onclick=async()=>{const x=await c.auth.mfa.enroll({factorType:'totp',friendlyName:'Bitey SBT'}); if(x.error){box.textContent=x.error.message;return;} factorId=x.data.id; box.innerHTML=`<p>${t('scan')}</p><img class="bitey-auth-qr" src="${x.data.totp.qr_code}" alt="TOTP QR"><div class="bitey-auth-actions"><button class="primary" id="ba-confirm2fa">${t('verify')}</button></div><label><input id="ba-mfa-code" inputmode="numeric" maxlength="6" autocomplete="one-time-code"></label><p class="bitey-auth-status" id="ba-status"></p>`; $('#ba-confirm2fa').onclick=async()=>{const ch=await c.auth.mfa.challenge({factorId}); if(ch.error){$('#ba-status').textContent=ch.error.message;return;} const v=await c.auth.mfa.verify({factorId,challengeId:ch.data.id,code:$('#ba-mfa-code').value.trim()}); if(v.error){$('#ba-status').textContent=v.error.message;return;} session=v.data.session; render();}; };
  }
  function wireFetch(){ const original=window.fetch; window.fetch=async(i,o={})=>{if(session?.access_token){const u=typeof i==='string'?i:i?.url||'';if(u.includes('/api/v1/'))o={...o,headers:{...(o.headers||{}),Authorization:'Bearer '+session.access_token}};}return original(i,o)}; }
  function boot(){ document.documentElement.lang=lang; style(); modal(); bar(); wireFetch(); void refresh(); window.BiteyAuth={open,close,getSession:()=>session,setLanguage,language:()=>lang,signOut:async()=>{await supabase?.auth.signOut();session=null;renderBar();}}; }
  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',boot,{once:true}); else boot();
})();
