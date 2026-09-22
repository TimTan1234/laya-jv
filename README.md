# laya-decision — Luna-customized laya

Self-hosted deployment of [laya](https://github.com/NandhaKishorM/laya)
(Apache-2.0 non-autoregressive System 1 decision engine), packaged as a Docker
HTTP service for the **Luna** app. It replaces Luna's dependency on the closed
TypeSafe (Jev) cloud API for plan-gap suggestions with a local model.

## What's inside

- `laya-src/` — vendored laya engine (v0.3.4) from the upstream repo
- `server.py` — FastAPI wrapper around `Agent.system_one()`
- `Dockerfile` — CPU-only image; the checkpoint is pre-downloaded at build
  time, so the container runs fully offline. Default checkpoint:
  `convaiinnovations/laya:multilingual` (Luna serves English **and** Chinese
  users; the English-only checkpoint cannot read zh text).

## Endpoints

| Method | Path | Purpose |
|---|---|---|
| GET | `/health` | liveness, loaded checkpoint + device |
| POST | `/v1/system-one` | generic laya call: `{state, questions}` → `{answers, usage}` |
| POST | `/v1/luna/plan-gap-check` | Luna preset: `{plannedItems}` → `{gaps, coverage}` |

The generic `/v1/system-one` answer shape mirrors the TypeSafe SDK
(`answers.<qid>.noul` / `.choice` / `.score`), so Luna's backend can swap
between them with one code path.

## Run (plain docker)

```bash
./run.sh                    # builds if needed, runs on port 8100
LAYA_PORT=9000 ./run.sh     # different host port
```

or:

```bash
docker build -t laya-decision:latest .
docker run -d --name laya-decision --restart unless-stopped -p 8100:8100 laya-decision:latest
```

## Run (docker compose, from the luna repo)

The luna `docker-compose.yml` includes this service (built from `../laya`);
luna-api reaches it at `http://laya:8100` over the compose network.

## GPU acceleration

Laya runs on CPU by default (193-464 ms/request). To use a NVIDIA GPU
(4 GB VRAM is enough — the multilingual checkpoint needs ~1.3 GB fp32 weights
plus activations):

```bash
USE_GPU=1 ./run.sh                                  # plain docker run
# or with compose:
docker compose -f docker-compose.yml -f docker-compose.gpu.yml up -d
```

This builds `laya-decision:gpu` (CUDA torch 2.5.1+cu121, works with Windows/WSL
driver >= 530) and starts it with `--gpus all`. The engine auto-detects CUDA
and falls back to CPU if the runtime is unavailable.

On WSL2 the GPU comes from the **Windows** NVIDIA driver — there is nothing to
install inside WSL. If `nvidia-smi` is not found in WSL / `--gpus all` fails
with "no adapters were found", update the NVIDIA driver on Windows (Game Ready
or Studio, >= 530 for CUDA 12.1) and restart the WSL VM
(`wsl --shutdown` from PowerShell) before retrying.

On **native Linux** you need the NVIDIA driver (>= 530) **and** the NVIDIA
Container Toolkit, plus Docker configured to use it:

```bash
sudo nvidia-ctk runtime configure --runtime=docker
sudo systemctl restart docker
docker run --rm --gpus all laya-decision:gpu nvidia-smi   # smoke test
```

## Try it

```bash
curl -s -X POST http://localhost:8100/v1/luna/plan-gap-check \
  -H 'Content-Type: application/json' \
  -d '{"plannedItems":[{"time":"19:30","title":"Rooftop dinner","tag":"food"}]}'
# {"gaps":["breakfast","lunch"],"coverage":{"breakfast":..,"lunch":..,"dinner":..}, ...}
```

## Configuration

| Env var | Default | Meaning |
|---|---|---|
| `LAYA_MODEL` | `multilingual` | checkpoint subfolder: `multilingual`, `english`, or `typed-decisions` |
| `LAYA_MODEL_REPO` | `convaiinnovations/laya` | HF repo |
| `LAYA_DEVICE` | auto | force `cpu`/`cuda`/`mps` |
| `OMP_NUM_THREADS` | `4` | CPU inference threads |

## Honest model caveat

Luna's plan-gap questions were originally written for the closed Jev API.
Measured locally, laya's public checkpoints rank the covered meals correctly in
English (`typed-decisions` ranks best) but their probability margins are small,
so Luna's 0.3 gap threshold may under-flag. The multilingual checkpoint is the
default because it is the only one that reads Luna's Chinese plans; switch to
`LAYA_MODEL=typed-decisions` if you serve English only.
