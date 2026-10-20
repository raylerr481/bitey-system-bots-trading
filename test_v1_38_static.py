from pathlib import Path
import re, json
p=Path(__file__).with_name('Bitey_SBT_MultiModel_Engine_v1_38.mq4')
s=p.read_text(encoding='utf-8')
# Strip comments and string/char literals before delimiter checks.
def strip_cpp(text):
    out=[]; i=0; state='code'
    while i<len(text):
        c=text[i]; n=text[i+1] if i+1<len(text) else ''
        if state=='code':
            if c=='/' and n=='/': state='line'; out.extend('  '); i+=2; continue
            if c=='/' and n=='*': state='block'; out.extend('  '); i+=2; continue
            if c=='"': state='string'; out.append(' '); i+=1; continue
            if c=="'": state='char'; out.append(' '); i+=1; continue
            out.append(c); i+=1
        elif state=='line':
            if c=='\n': state='code'; out.append('\n')
            else: out.append(' ')
            i+=1
        elif state=='block':
            if c=='*' and n=='/': state='code'; out.extend('  '); i+=2
            else: out.append('\n' if c=='\n' else ' '); i+=1
        elif state in ('string','char'):
            if c=='\\': out.extend('  '); i+=2
            elif (state=='string' and c=='"') or (state=='char' and c=="'"): state='code'; out.append(' '); i+=1
            else: out.append('\n' if c=='\n' else ' '); i+=1
    return ''.join(out),state
clean,state=strip_cpp(s)
assert state=='code',f'unterminated lexical state {state}'
for left,right in [('(',')'),('{','}'),('[',']')]:
    depth=0
    for idx,c in enumerate(clean):
        if c==left: depth+=1
        elif c==right:
            depth-=1
            assert depth>=0, f'extra {right} at {idx}'
    assert depth==0, f'unbalanced {left}{right}: {depth}'
checks={
 'version property': '#property version   "1.38"' in s,
 'all internal versions updated': 'v1.32' not in s and '1.36' not in s and 'v1_36' not in s,
 'no account-type filter': 'InpRequireDemoAccount' not in s and 'AccountTypeFilter=none' in s,
 'risk defaults preserved': all(x in s for x in ['InpOperatingCapitalUSD = 500.0','InpRiskPerTradeUSD = 1.25','InpHardRiskCapUSD = 2.00']),
 'bidirectional signals preserved': all(x in s for x in ['BUY candidate','SELL candidate','OP_BUY','OP_SELL']),
 'SBT snapshot endpoint configured': '/api/v1/mt4/bitey-report' in s,
 'closed-trade endpoint configured': '/api/v1/mt4/trade-closed' in s,
 'Q-learning transition payload': all(x in s for x in ['Q_LEARNING','state_id','reward_r','next_state_id','terminal']),
 'trade close management': 'TIME EXIT | ticket=' in s and 'TIME EXIT FAILED' in s,
 'CSV versioned': 'Bitey_SBT_Evidence_v1_38.csv' in s,
 'entry-state persistence': all(x in s for x in ['GlobalVariableSet(TicketGlobalKey("state"','GlobalVariableSet(TicketGlobalKey("risk"','GlobalVariableSet(TicketGlobalKey("model"']),
}
for k,v in checks.items(): print(('PASS' if v else 'FAIL')+' | '+k)
assert all(checks.values())
print(f'PASS | delimiter balance; {len(s.splitlines())} lines; {p.stat().st_size} bytes')
