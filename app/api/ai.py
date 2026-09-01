"""ChatGPT-powered research assistant for TradingSystemBot.

The model is advisory only. It cannot bypass deterministic risk controls or execute orders.
"""
import os
from typing import Literal

import httpx
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field

router = APIRouter(prefix="/api/v1/ai", tags=["ai"])

class ChatRequest(BaseModel):
    message: str = Field(min_length=1, max_length=8000)
    language: Literal["es", "pt", "en"] = "es"

LANGUAGE_NAMES = {"es": "Spanish", "pt": "Portuguese", "en": "English"}
SYSTEM_PROMPT = """You are TradingSystemBot Analyst, an AI research assistant inside an algorithmic trading platform.
Primary responsibilities: explain markets and strategies, compare hypotheses, interpret backtests, identify risks, and help users design controlled experiments.
Never promise profits. Never present an estimate as a guarantee. Never instruct the user to bypass risk controls. Real-money execution is disabled in the current system milestone.
The deterministic TradingSystemBot risk engine has priority over your suggestions.
Answer in the requested language, using clear language for beginners while allowing technical depth when useful.
"""

@router.get("/status")
def ai_status():
    return {"provider": "OpenAI", "api": "Responses", "configured": bool(os.getenv("OPENAI_API_KEY")), "role": "research-and-analysis", "execution_authority": False}

@router.post("/chat")
async def chat(request: ChatRequest):
    key = os.getenv("OPENAI_API_KEY")
    if not key:
        raise HTTPException(status_code=503, detail="OPENAI_API_KEY is not configured")

    prompt = f"{SYSTEM_PROMPT}\nRespond in {LANGUAGE_NAMES[request.language]}.\n\nUser request:\n{request.message}"
    headers = {"Authorization": f"Bearer {key}", "Content-Type": "application/json"}
    payload = {
        "model": os.getenv("OPENAI_MODEL", "gpt-5.6-luna"),
        "input": prompt,
        "store": False,
    }
    async with httpx.AsyncClient(timeout=45) as client:
        response = await client.post("https://api.openai.com/v1/responses", headers=headers, json=payload)
    if response.status_code >= 400:
        raise HTTPException(status_code=502, detail="OpenAI request failed")
    data = response.json()
    text = data.get("output_text")
    if not text:
        chunks = []
        for item in data.get("output", []):
            for content in item.get("content", []):
                if content.get("type") == "output_text":
                    chunks.append(content.get("text", ""))
        text = "\n".join(chunks).strip()
    return {"reply": text or "No se obtuvo una respuesta de la IA.", "model": data.get("model"), "provider": "OpenAI"}
