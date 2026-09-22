"""Laya decision-engine HTTP service, customized for the Luna app.

Exposes laya's non-autoregressive System 1 decision model over HTTP so Luna's
Node backend can call it locally instead of the closed TypeSafe (Jev) cloud API.

Endpoints:
  GET  /health                    -> liveness + which checkpoint/device is loaded
  POST /v1/system-one             -> generic: {state, questions} -> laya answers
  POST /v1/luna/plan-gap-check    -> Luna preset: {plannedItems} -> {coverage, gaps}
"""

import os

import laya
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field

MODEL_REPO = os.environ.get("LAYA_MODEL_REPO", "convaiinnovations/laya")
# Luna serves English and Chinese users, so the multilingual checkpoint is the
# default: it reads both, and the English-only checkpoint collapses on zh text.
MODEL_SUBFOLDER = os.environ.get("LAYA_MODEL", "multilingual")
DEVICE = os.environ.get("LAYA_DEVICE") or None

app = FastAPI(title="laya-decision", version="1.0.0")

agent = None
model_label = None


@app.on_event("startup")
def load_agent():
    global agent, model_label
    model_label = f"{MODEL_REPO}:{MODEL_SUBFOLDER}"
    print(f"[laya-decision] loading {model_label} ...", flush=True)
    agent = laya.load(MODEL_REPO, subfolder=MODEL_SUBFOLDER, device=DEVICE)
    print(f"[laya-decision] ready on {agent.device}", flush=True)


class SystemOneRequest(BaseModel):
    state: object = Field(..., description="Text string, JSON dict, or turn list to evaluate")
    questions: dict = Field(..., description="question_id -> {type, instructions, criteria?}")


@app.get("/health")
def health():
    return {
        "status": "ok",
        "model": model_label,
        "device": str(agent.device) if agent else "loading",
        "version": laya.__version__,
    }


@app.post("/v1/system-one")
def system_one(req: SystemOneRequest):
    if agent is None:
        raise HTTPException(status_code=503, detail="model still loading")
    try:
        return agent.system_one(req.state, req.questions)
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


# --- Luna preset: date-plan meal gap check (server/ai.ts PLAN_GAP_SLOTS) ---

LUNA_PLAN_GAP_QUESTIONS = {
    "breakfast": {
        "type": "noul",
        "instructions": "Does the plan include a morning meal or breakfast-style activity before roughly 11am?",
    },
    "lunch": {
        "type": "noul",
        "instructions": "Does the plan include a midday meal around roughly 12pm-2pm?",
    },
    "dinner": {
        "type": "noul",
        "instructions": "Does the plan include an evening meal around roughly 6pm-9pm?",
    },
}


class PlanGapRequest(BaseModel):
    plannedItems: list = Field(..., description="[{time: 'HH:MM', title: str, tag: str|null}]")


@app.post("/v1/luna/plan-gap-check")
def luna_plan_gap_check(req: PlanGapRequest):
    """Convenience preset: same contract as Luna's /api/ai/plan-gap-check response."""
    if agent is None:
        raise HTTPException(status_code=503, detail="model still loading")
    result = agent.system_one({"plannedItems": req.plannedItems}, LUNA_PLAN_GAP_QUESTIONS)
    coverage = {slot: result["answers"][slot]["noul"] for slot in LUNA_PLAN_GAP_QUESTIONS}
    gaps = [slot for slot, p in coverage.items() if p < 0.3]
    return {"gaps": gaps, "coverage": coverage, "model": model_label}
