# Bing-Grounded Research Agents on Azure AI Foundry

Two Jupyter notebooks demonstrating Azure AI Foundry **PromptAgents** with
**Grounding with Bing Search**, plus a three-layer citation guardrail pipeline
and an offline evaluation harness. Infrastructure is declared in **Bicep** under `infra/`:

```
infra/
  modules/
    foundry/foundry.bicep                  # AI Services account + project + model deployment
    bing-grounding/bing-grounding.bicep    # Bing.Grounding account + project connection
  main.bicep                               # composes the two modules
  deploy.ps1                               # CLI wrapper that reads .env
  clean-up-resources.ipynb                 # tears down the RG
  README.md
transfer-pricing-bulk-research.ipynb
regulatory-monitoring.ipynb
requirements.txt
.env.example
```

All notebooks target the **GA** stack:

- `agent-framework-foundry` (Microsoft Agent Framework + Foundry connectors)
- `azure-ai-projects >= 2.0` (PromptAgent, `BingGroundingTool`)
- `azure-identity` (`AzureCliCredential` / `DefaultAzureCredential`)
- `azure-ai-evaluation` (`GroundednessEvaluator`, `evaluate`)
- Foundry control-plane API `2025-06-01`
- Model deployment `gpt-5.1` (model version `2025-11-13`)
- Bing resource API `2020-06-10`

## Notebooks

| Notebook | Agent | Use case |
|---|---|---|
| `regulatory-monitoring.ipynb` | `RegulatoryMonitorAgent` | Client-tailored regulatory monitoring briefs |
| `transfer-pricing-bulk-research.ipynb` | `TransferPricingComparablesAgent` | Bulk structured business descriptions for comparable-company analysis (OECD TP Guidelines, FAR analysis) |

Each notebook follows the same structure:

1. **Provisioning** (optional, idempotent) — resource group, Foundry account +
   project, model deployment, `Microsoft.Bing/accounts` (`Bing.Grounding`),
   and a Foundry connection wiring Bing into the project.
2. **Configure** — reads endpoint and connection IDs from a `.env` file.
3. **Provision PromptAgent(s)** via `azure.ai.projects.AIProjectClient` with
   `BingGroundingTool` attached.
4. **Single-run sanity check** via `FoundryAgent` from `agent-framework-foundry`.
5. **Workflow specific to the use case** (structured per-client queries for
   regulatory monitoring; concurrent bulk runner with retries and resumable
   JSONL checkpoint for transfer-pricing comparables).
6. **Citation Guardrail Pipeline** — three layers:
   - **Layer 1** — Groundedness Detection via Azure AI Content Safety (optional)
   - **Layer 2** — URL reachability via `httpx` + cross-check against Bing
     tool results (required default)
   - **Layer 3** — Destination content safety on cited pages (optional)
7. **Batch Groundedness Evaluation** using `azure-ai-evaluation`'s
   `GroundednessEvaluator`, with optional Foundry-portal upload. Requires a
   judge-model deployment set via `EVAL_JUDGE_DEPLOYMENT_NAME` (see Notes).

## Prerequisites

1. An **Azure AI Foundry** project — copy the project endpoint from the
   Foundry portal Overview page.
2. A model deployment in that project (e.g. `gpt-5.1`).
3. A **Grounding with Bing Search** resource connected to the project — copy
   its connection ID (full ARM resource id) from the Connected Resources page.
4. Azure CLI logged in: `az login`.
5. Python 3.11+ (3.12 recommended).

If you don't have these yet, the **Provisioning** section at the top of each
notebook creates them idempotently from `az` CLI commands. You need permissions
to create resources in the target subscription.

## Setup

```powershell
# From the repo root
python -m venv .venv
.\.venv\Scripts\Activate.ps1

pip install -r requirements.txt

az login
```

Copy `.env.example` to `.env` and fill in:

```dotenv
AZURE_AI_PROJECT_ENDPOINT=https://<your-foundry-acct>.services.ai.azure.com/api/projects/<your-project>
AZURE_AI_MODEL_DEPLOYMENT_NAME=gpt-5.1
BING_CONNECTION_ID=/subscriptions/.../connections/<bing-grounding-conn>
# Optional — defaults to the AI Services account base URL derived from PROJECT_ENDPOINT
CONTENT_SAFETY_ENDPOINT=https://<your-foundry-acct>.cognitiveservices.azure.com/
# Judge-model deployment for the batch evaluation harness. Leave empty to skip
# groundedness scoring. See README "Batch evaluation" section for why.
EVAL_JUDGE_DEPLOYMENT_NAME=gpt-4o-mini
```

## Provisioning

If your Foundry project, model deployment, and Bing connection already exist,
**skip provisioning** — just point `.env` at them and run the notebooks.

Otherwise, you have two equivalent options:

### Option A — from the shell

```powershell
.\infra\deploy.ps1
```

Reads `.env`, ensures the resource group exists, deploys `infra/main.bicep`,
and prints the values you need back in `.env` (`AZURE_AI_PROJECT_ENDPOINT`,
`AZURE_AI_MODEL_DEPLOYMENT_NAME`, `BING_CONNECTION_ID`).

### Option B — from the notebook

Run the **(Optional) Provision Azure resources** cell at the top of any
notebook. It deploys the same `infra/main.bicep` via the Azure CLI and pipes
outputs into the kernel environment so the **Configure** cell picks them up.

See `infra/README.md` for the full provisioning story (what gets created,
clean-up, re-runs).

## Running

Open any notebook in VS Code (or `jupyter lab`) against the `.venv` kernel and
run cells top-to-bottom. If your Foundry project, model deployment, and Bing
connection already exist, skip the provisioning section and jump straight to
**Configure**.

A reasonable first pass on `transfer-pricing-bulk-research.ipynb`:

1. Run **Configure** — verifies `.env` is wired.
2. Run **Provision the transfer-pricing comparables PromptAgent** — creates a
   versioned PromptAgent server-side.
3. Run **Single-run sanity check** — one company, end-to-end smoke test.
4. Run **Bulk company research** with the 5-row demo list — exercises the
   concurrent runner, retries, and the JSONL checkpoint.
5. Run **Layer 2** of the guardrail pipeline against the demo output to verify
   citations are reachable.
6. Run the **batch evaluation** cell — produces averaged groundedness and
   citation-reachability scores across a small inline dataset.

## Repository layout

```
infra/                                      Provisioning
  modules/                                    Shared Bicep modules
    foundry/foundry.bicep                       AI Services account + project + model deployment
    bing-grounding/bing-grounding.bicep         Bing.Grounding account + project connection
  main.bicep                                  Composes the two modules
  deploy.ps1                                  CLI wrapper that reads .env
  clean-up-resources.ipynb                    Tears down the RG
  README.md                                   Provisioning docs
.env.example                                Template for required environment variables
requirements.txt                            Runtime dependencies
regulatory-monitoring.ipynb                 Per-client regulatory briefs
transfer-pricing-bulk-research.ipynb        Bulk TP comparables (OECD FAR analysis)
```

## Notes

### Batch evaluation: judge model

`GroundednessEvaluator` (from `azure-ai-evaluation`) sends the OpenAI parameter
`max_tokens` to its judge model. **`gpt-5.x` deployments reject `max_tokens`**
— they require `max_completion_tokens` — and the eval run fails 100% of rows
with HTTP 400. The evaluator hard-codes this in its prompty template, so the
fix is to point the judge at a different deployment.

In `.env`, set `EVAL_JUDGE_DEPLOYMENT_NAME` to the name of a `gpt-4o`,
`gpt-4o-mini`, or `gpt-4.1` deployment in the same Foundry account. The judge
does **not** need to match the agent model. This variable is **required** by
the batch-evaluation cells; the notebooks raise a `RuntimeError` if it is unset.

### Other

- Provisioning the PromptAgent creates a **new versioned agent** server-side
  each time `ensure_agent()` runs. Old versions remain unless explicitly
  deleted from the Foundry portal.
- The bulk runner's "unit of parallelism" is the whole agent run (one company
  per task). For larger jobs, the same `run_research(...)` coroutine is the
  work item for Azure Container Apps jobs, Service Bus / Storage Queue
  workers, or Azure Functions queue triggers.
- The eval harness calls the target synchronously on worker threads; the
  async agent invocation is bridged via `asyncio.run(...)` inside a plain
  sync wrapper. To publish results to the Foundry portal, fill in the
  commented-out `azure_ai_project={...}` argument to `evaluate()`.
