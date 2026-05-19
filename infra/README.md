# Provisioning (Bicep)

Declarative provisioning of the Foundry + Grounding-with-Bing-Search
infrastructure shared by all notebooks:

```
infra/
  modules/
    foundry/foundry.bicep               # AI Services account + project + model deployment
    bing-grounding/bing-grounding.bicep # Bing.Grounding account + project connection
  main.bicep                            # composes the two modules
  deploy.ps1                            # CLI wrapper that reads .env
  clean-up-resources.ipynb              # tears the RG down
```

## Deploy

### From the shell

Set `AZURE_SUBSCRIPTION_ID` (and any optional overrides) in `.env`, then:

```powershell
.\infra\deploy.ps1
```

`deploy.ps1` reads `.env`, creates the resource group if missing, runs
`az deployment group create -f main.bicep`, and prints the outputs you need
back in `.env` (`AZURE_AI_PROJECT_ENDPOINT`, `AZURE_AI_MODEL_DEPLOYMENT_NAME`,
`BING_CONNECTION_ID`).

### From a notebook

Run the **Provision Azure resources** cell at the top of any of the 
notebooks. It calls the same `main.bicep` via the `az()` helper and pipes the
outputs into the kernel environment so the **Configure** cell picks them up.

### Direct `az` invocation

```powershell
az group create -n rg-foundry-bing-research -l eastus
az deployment group create `
  -g rg-foundry-bing-research `
  -f infra/main.bicep `
  --parameters `
    foundryAccountName=foundry-bing-research-acct `
    foundryProjectName=bing-research-proj `
    bingResourceName=bing-grounding-research
```

## What gets created

```
Microsoft.CognitiveServices/accounts            (kind=AIServices)         <-- foundry
  └── projects                                                            <-- foundryProject
  └── deployments                                                         <-- modelDeployment
Microsoft.Bing/accounts                          (kind=Bing.Grounding)     <-- bing
Microsoft.CognitiveServices/accounts/projects/connections                 <-- bingConnection
```

The Bing API key is read at deployment time via `listKeys()` and pushed into
the connection's `credentials` — it does **not** appear in the template, in
`.env`, or in deployment outputs.

## Clean up

Open `clean-up-resources.ipynb` and run all cells. It deletes the entire
resource group (and therefore everything `main.bicep` created). All notebooks share this infrastructure, so cleanup affects all of them.

## Re-running

`main.bicep` is fully idempotent. Re-running `deploy.ps1` after any `.env`
change will diff and update only what changed. The notebooks' provisioning
cell behaves identically.
