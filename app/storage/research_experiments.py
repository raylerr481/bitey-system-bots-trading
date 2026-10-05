"""Persistent experiment lineage store for Research -> MT4 -> Evidence -> Evolution -> Validation."""
from __future__ import annotations
import json, os
from urllib import request
from typing import Any

TABLE="research_experiments"

def enabled(): return bool(os.getenv("SUPABASE_URL") and os.getenv("SUPABASE_SERVICE_ROLE_KEY"))
def _headers():
    k=os.environ["SUPABASE_SERVICE_ROLE_KEY"]
    return {"apikey":k,"Authorization":f"Bearer {k}","Content-Type":"application/json","Prefer":"resolution=merge-duplicates,return=representation"}
def _url(): return os.environ["SUPABASE_URL"].rstrip("/") + f"/rest/v1/{TABLE}"

def upsert(payload: dict[str,Any]):
    if not enabled(): return {"persisted":False,"reason":"SUPABASE_NOT_CONFIGURED"}
    row=dict(payload)
    req=request.Request(_url(),data=json.dumps(row,default=str).encode(),headers=_headers(),method="POST")
    with request.urlopen(req,timeout=8) as r: body=r.read().decode() or "[]"
    parsed=json.loads(body)
    return {"persisted":True,"row":parsed[0] if isinstance(parsed,list) and parsed else parsed}

def get(experiment_id:str):
    if not enabled(): return None
    url=_url()+"?select=*&experiment_id=eq."+request.quote(experiment_id,safe="")+"&limit=1"
    req=request.Request(url,headers=_headers(),method="GET")
    with request.urlopen(req,timeout=8) as r: body=r.read().decode() or "[]"
    rows=json.loads(body)
    return rows[0] if rows else None

def list_recent(limit=100):
    if not enabled(): return []
    url=_url()+"?select=*&order=updated_at.desc&limit="+str(max(1,min(limit,500)))
    req=request.Request(url,headers=_headers(),method="GET")
    with request.urlopen(req,timeout=8) as r: body=r.read().decode() or "[]"
    rows=json.loads(body)
    return rows if isinstance(rows,list) else []
