# Terraform APIM Deployment — Enterprise Pattern Demo

This folder demonstrates the **recommended enterprise pattern** for deploying Azure API Management using Terraform, with:

- **Shared Terraform module** — enforces naming, policies, products, and subscriptions
- **Reusable CI/CD workflow** — one pipeline template, all teams consume it
- **Environment separation** — `dev.tfvars` / `prod.tfvars` + Terraform workspaces
- **PR-based workflow** — `terraform plan` on PRs, `terraform apply` on merge
- **Local state** — for this demo (teams should use remote state in Azure Storage)

## What Gets Deployed

| Resource | Description |
|---|---|
| Resource Group | `rg-apim-demo-{env}` |
| API Management | APIM instance with Developer SKU |
| API | Orders API imported from OpenAPI spec |
| API Version Set | Versioned API (v1) with URL segment scheme |
| API Policy | Rate limiting + CORS + header stripping |
| Backend | Backend service pointing to your API |
| Product | "Orders API Product" with subscription required |
| Product-API link | Associates the Orders API with the product |
| Subscription | Active subscription key scoped to the API |
| Named Value | Stores the backend URL as a config value |

## Prerequisites

1. **Terraform** >= 1.5.0 — [Install guide](https://developer.hashicorp.com/terraform/install)
2. **Azure CLI** — [Install guide](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli)
3. An **Azure subscription** with permissions to create resources

## Quick Start

### 1. Login to Azure

```bash
az login
az account set --subscription "<your-subscription-id>"
```

### 2. Update the `.tfvars` files

Edit `dev.tfvars` and `prod.tfvars` — at minimum change:

- `apim_name` — must be **globally unique** across all of Azure
- `publisher_email` — your email address

### 3. Deploy Dev

```bash
cd terraform

# Initialize Terraform (downloads providers)
terraform init

# Preview what will be created
terraform plan -var-file=dev.tfvars

# Deploy
terraform apply -var-file=dev.tfvars
```

> **Note**: APIM provisioning time depends on the SKU:
> - **V2 SKUs** (`BasicV2_1`, `StandardV2_1`) — **~5 minutes**
> - **Classic SKUs** (`Developer_1`, `Standard_1`, `Premium_1`) — **30-60 minutes**
>
> The default in this demo is `BasicV2_1`. If you use a classic SKU, be prepared to wait.

### 4. Deploy Prod

Since dev and prod use different state, you can use [Terraform workspaces](https://developer.hashicorp.com/terraform/language/state/workspaces) to manage them:

```bash
# Create and switch to prod workspace
terraform workspace new prod

# Deploy prod
terraform apply -var-file=prod.tfvars
```

Or if you prefer separate state directories:

```bash
# From a separate terminal/directory, or use -chdir
terraform init
terraform apply -var-file=prod.tfvars
```

### 5. Verify Deployment

After `terraform apply` completes:

```bash
# See all outputs
terraform output

# Get the API gateway URL
terraform output apim_gateway_url

# Get the subscription key (sensitive)
terraform output -raw subscription_primary_key
```

### 6. Test the API

```bash
# Get the values
GATEWAY_URL=$(terraform output -raw apim_gateway_url)
SUB_KEY=$(terraform output -raw orders_api_subscription_key)

# Call the API
curl -H "Ocp-Apim-Subscription-Key: $SUB_KEY" "$GATEWAY_URL/orders/v1/orders"
```

## Architecture — What's Happening

```
┌─────────────────────────────────────────────────────────────────────────┐
│  Platform Team (builds once)                                            │
│                                                                         │
│   modules/apim-api/        →  Enforces naming, policies, products,     │
│                                subscriptions for every API              │
│                                                                         │
│   deploy-terraform.yaml    →  Reusable CI/CD workflow                  │
│                                (plan on PR, apply on merge)             │
├─────────────────────────────────────────────────────────────────────────┤
│  Product Team (per API)                                                 │
│                                                                         │
│   main.tf                  →  Calls the module (tiny file!)            │
│   api_specs/orders-api.yaml→  OpenAPI spec (source of truth)           │
│   policies/api-policy.xml  →  API policies (rate limit, CORS, etc.)    │
│   dev.tfvars / prod.tfvars →  Environment-specific config              │
│   deploy-apim-terraform.yaml→ Calls the reusable workflow              │
└─────────────────────────────────────────────────────────────────────────┘
```

**Key point for the customer**: A product team's `main.tf` is just this:

```hcl
module "orders_api" {
  source = "./modules/apim-api"       # In real org: git::https://github.com/org/modules.git//apim-api?ref=v1.0

  apim_name        = azurerm_api_management.apim.name
  resource_group   = azurerm_resource_group.rg.name
  api_name         = "orders-api"
  api_display_name = "Orders API"
  api_path         = "orders"
  openapi_spec     = file("${path.module}/api_specs/orders-api.yaml")
  policy_xml       = file("${path.module}/policies/api-policy.xml")
  backend_url      = var.backend_url
}
```

Adding a second API = duplicate the block, change 4 values. Same standards, same pipeline.

## File Structure

```
terraform/
├── main.tf                          # APIM instance + module calls (this is what teams write)
├── variables.tf                     # Input variable definitions
├── outputs.tf                       # Output values (URLs, keys)
├── dev.tfvars                       # Dev environment values
├── prod.tfvars                      # Prod environment values
├── modules/
│   └── apim-api/                    # ← Shared module (platform team owns this)
│       ├── main.tf                  #    API + version set + policy + backend + product + subscription
│       ├── variables.tf             #    Module inputs
│       └── outputs.tf               #    Module outputs (API ID, subscription keys)
├── api_specs/
│   └── orders-api.yaml              # OpenAPI spec (source of truth for API operations)
├── policies/
│   └── api-policy.xml               # API-level policy (rate limit, CORS, headers)
└── README.md                        # This file

.github/workflows/
├── deploy-terraform.yaml            # ← Reusable workflow (platform team owns this)
└── deploy-apim-terraform.yaml       # ← Caller workflow (product team writes this)
```

## Common Operations

### Make a change to the API

1. Edit `api_specs/orders-api.yaml` (add/remove operations, update schemas)
2. Run `terraform plan -var-file=dev.tfvars` to see the diff
3. Run `terraform apply -var-file=dev.tfvars` to deploy

### Update a policy

1. Edit `policies/api-policy.xml`
2. Run `terraform apply -var-file=dev.tfvars`

### Check for drift (someone changed APIM in the portal)

```bash
terraform plan -var-file=dev.tfvars
```

If there's drift, the plan will show what changed. Apply to bring it back in sync.

### Destroy everything

```bash
# Destroy dev
terraform destroy -var-file=dev.tfvars

# Switch to prod workspace and destroy
terraform workspace select prod
terraform destroy -var-file=prod.tfvars
```

## CI/CD — The Big Picture

```
Developer                  GitHub                           Azure
───────                    ──────                           ─────

1. Edit files:
   - api_specs/orders-api.yaml    (API definition)
   - policies/api-policy.xml      (policies)
   - main.tf                      (add/change API module)
   - dev.tfvars / prod.tfvars     (env config)
        │
        ▼
2. Push branch → Open PR to main
        │
        ▼
┌─────────────────────────────────────────────────┐
│  deploy-apim-terraform.yaml triggers            │
│  (because files in terraform/** changed)        │
│                                                 │
│  Calls deploy-terraform.yaml TWICE:             │
│                                                 │
│  ┌─────────────┐    ┌─────────────┐            │
│  │ plan-dev    │    │ plan-prod   │  parallel   │──▶ No changes to Azure
│  │ plan only   │    │ plan only   │             │    (just shows what WOULD change)
│  └─────────────┘    └─────────────┘            │
└─────────────────────────────────────────────────┘
        │
        ▼
3. Reviewer reads the plan output in the PR
   "OK, this adds 1 API operation and changes a policy"
   → Approves and merges PR
        │
        ▼
┌─────────────────────────────────────────────────┐
│  deploy-apim-terraform.yaml triggers AGAIN      │
│  (push to main)                                 │
│                                                 │
│  Calls deploy-terraform.yaml TWICE:             │
│                                                 │
│  ┌─────────────┐    ┌──────────────┐           │
│  │ deploy-dev  │───▶│ deploy-prod  │ sequential │──▶ ACTUALLY deploys to Azure
│  │ plan+apply  │    │ plan+apply   │           │
│  └─────────────┘    └──────────────┘           │
│                      (waits for dev             │
│                       + approval gate)          │
└─────────────────────────────────────────────────┘
        │
        ▼
4. Azure APIM (dev) has the changes
   Azure APIM (prod) has the changes
```

Two GitHub Actions workflows handle deployment. The split is intentional — it separates **what** to deploy (caller) from **how** to deploy (reusable):

| Workflow | Who Writes It | What It Does |
|---|---|---|
| `deploy-terraform.yaml` | Platform team (once) | The Terraform engine — init, plan, apply |
| `deploy-apim-terraform.yaml` | Product team (per API) | The dispatcher — "deploy dev then prod" |

### Workflow 1: `deploy-apim-terraform.yaml` — The Dispatcher

**This file doesn't run any Terraform itself.** It just calls the reusable workflow with the right inputs, like making phone calls:

- "Hey `deploy-terraform.yaml`, deploy **dev** using **dev.tfvars**"
- "Hey `deploy-terraform.yaml`, deploy **prod** using **prod.tfvars**"

**Triggers:**

```yaml
on:
  push:
    branches: [main]          # someone merges to main
    paths: ["terraform/**"]   # AND changed files in terraform/ folder
  pull_request:
    branches: [main]          # someone opens a PR to main
    paths: ["terraform/**"]
```

**Path filtering**: Only triggers when files in `terraform/` change. Changes to `apimartifacts/`, `openapi.yaml`, or other files don't trigger this workflow.

**On Pull Request** — runs plan only (no changes to Azure):

```yaml
  plan-dev:
    if: github.event_name == 'pull_request'
    uses: ./.github/workflows/deploy-terraform.yaml
    with:
      environment: dev
      working_directory: terraform
      tf_var_file: dev.tfvars
      plan_only: true              # ← plan only, don't touch Azure
    secrets: inherit

  plan-prod:                       # runs in parallel with plan-dev
    if: github.event_name == 'pull_request'
    uses: ./.github/workflows/deploy-terraform.yaml
    with:
      environment: prod
      working_directory: terraform
      tf_var_file: prod.tfvars
      plan_only: true
    secrets: inherit
```

**On merge to main** — deploys dev first, then prod:

```yaml
  deploy-dev:
    if: github.event_name == 'push'
    uses: ./.github/workflows/deploy-terraform.yaml
    with:
      environment: dev
      working_directory: terraform
      tf_var_file: dev.tfvars      # plan_only defaults to false → will apply
    secrets: inherit

  deploy-prod:
    if: github.event_name == 'push'
    needs: deploy-dev              # ← waits for dev to succeed first
    uses: ./.github/workflows/deploy-terraform.yaml
    with:
      environment: prod
      working_directory: terraform
      tf_var_file: prod.tfvars
    secrets: inherit
```

### Workflow 2: `deploy-terraform.yaml` — The Worker

**This is where Terraform actually runs.** It doesn't know or care about APIM — it just runs Terraform for whatever folder and tfvars it's given.

**Trigger**: `workflow_call` only — cannot be triggered directly. Only called by other workflows.

**Inputs it accepts:**

| Input | Required | Default | Description |
|---|---|---|---|
| `environment` | Yes | — | Target environment name (`dev`, `prod`) — must match a GitHub Environment |
| `working_directory` | Yes | — | Path to the Terraform root module (e.g. `terraform`) |
| `tf_var_file` | Yes | — | `.tfvars` file to use (e.g. `dev.tfvars`) |
| `terraform_version` | No | `1.9.0` | Terraform version to install |
| `plan_only` | No | `false` | If `true`, runs `plan` but skips `apply` — used for PR checks |

**What it does step by step:**

```
Step 1: Checkout code
        └─ Gets the repo with all .tf files, api_specs/, policies/

Step 2: Setup Terraform
        └─ Installs Terraform 1.9.0 on the GitHub runner

Step 3: Azure Login
        └─ Authenticates to Azure using OIDC (client-id + tenant-id + subscription-id)
        └─ These secrets come from the GitHub Environment (dev or prod)

Step 4: terraform init
        └─ Downloads the azurerm provider
        └─ Initializes the working directory

Step 5: terraform workspace select <env>
        └─ Switches to "dev" or "prod" workspace
        └─ This keeps dev state and prod state SEPARATE
        └─ (creates the workspace if it doesn't exist yet)

Step 6: terraform plan -var-file=dev.tfvars -out=tfplan
        └─ Reads main.tf → sees module "orders_api"
        └─ Module reads api_specs/orders-api.yaml via file()
        └─ Module reads policies/api-policy.xml via file()
        └─ Compares desired state (code) vs actual state (Azure)
        └─ Outputs: "I will create/change/destroy X resources"
        └─ Saves the plan to tfplan file

Step 7: terraform apply tfplan                    ← SKIPPED if plan_only=true
        └─ Executes the saved plan
        └─ Creates/updates in Azure:
           ├─ Resource Group
           ├─ APIM Instance
           ├─ API (from OpenAPI spec)             ← orders-api.yaml gets deployed here
           ├─ API Policy (from XML)               ← api-policy.xml gets applied here
           ├─ API Version Set
           ├─ Backend
           ├─ Product
           ├─ Product ↔ API link
           ├─ Subscription
           └─ Named Value
```

**Key design choices:**

- **Workspaces**: Each environment gets its own Terraform workspace, so dev and prod have separate state files even with local state
- **Plan output saved**: The plan is saved to `tfplan` file, and `apply` uses that exact plan — no surprises between plan and apply
- **Environment protection**: When `plan_only=false`, the job is linked to a GitHub Environment, so approval gates on `prod` are respected
- **Secrets via `inherit`**: Caller workflows pass secrets with `secrets: inherit` — the reusable workflow reads `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, and `AZURE_SUBSCRIPTION_ID` from the environment

### End-to-End Example: Adding a New API Endpoint

A developer adds a new `/orders/{id}/status` endpoint. Here's exactly what happens:

```
1. Developer edits terraform/api_specs/orders-api.yaml
   (adds the new GET /orders/{id}/status operation)

2. Pushes branch "feature/order-status" → Opens PR to main

3. GitHub sees terraform/** changed → triggers deploy-apim-terraform.yaml

4. deploy-apim-terraform.yaml calls deploy-terraform.yaml TWICE:

   ┌─ Call 1: plan-dev ─────────────────────────────────────────┐
   │  inputs:                                                    │
   │    environment = "dev"                                      │
   │    tf_var_file = "dev.tfvars"                              │
   │    plan_only = true                                         │
   │                                                             │
   │  deploy-terraform.yaml runs:                                │
   │    terraform init                                           │
   │    terraform workspace select dev                           │
   │    terraform plan -var-file=dev.tfvars                      │
   │      → Output: "1 resource will be UPDATED"                │
   │      → "azurerm_api_management_api.this: import changed"   │
   │    terraform apply → SKIPPED (plan_only=true)              │
   └─────────────────────────────────────────────────────────────┘

   ┌─ Call 2: plan-prod (same thing, with prod.tfvars) ─────────┐
   │    → Output: "1 resource will be UPDATED"                   │
   └─────────────────────────────────────────────────────────────┘

5. Reviewer sees both plans in the PR → "Looks good, just one API update"
   → Approves and merges

6. Merge triggers push to main → deploy-apim-terraform.yaml fires again

7. This time it runs deploy jobs (plan_only defaults to false):

   ┌─ Call 1: deploy-dev ───────────────────────────────────────┐
   │  deploy-terraform.yaml runs:                                │
   │    terraform init                                           │
   │    terraform workspace select dev                           │
   │    terraform plan -var-file=dev.tfvars -out=tfplan          │
   │    terraform apply tfplan                                   │
   │      → Updates the API in dev APIM with new operation       │
   │      → ✅ Done                                              │
   └─────────────────────────────────────────────────────────────┘
                           │
                           ▼ (needs: deploy-dev)
   ┌─ Call 2: deploy-prod ──────────────────────────────────────┐
   │  (if prod has approval gate → reviewer approves first)      │
   │  deploy-terraform.yaml runs:                                │
   │    terraform init                                           │
   │    terraform workspace select prod                          │
   │    terraform plan -var-file=prod.tfvars -out=tfplan         │
   │    terraform apply tfplan                                   │
   │      → Updates the API in prod APIM with new operation      │
   │      → ✅ Done                                              │
   └─────────────────────────────────────────────────────────────┘

8. Both dev and prod APIM now have the new /orders/{id}/status endpoint
```

### Why Two Workflow Files Instead of One?

You could put everything in one file. The split is intentional for enterprise scale:

- **`deploy-terraform.yaml`** = the Terraform logic (init, plan, apply). Written **once** by the platform team. Reused by every product team
- **`deploy-apim-terraform.yaml`** = "I want dev then prod." Written by each product team. **Tiny** — just 4 job definitions

If you had 10 API teams, all 10 would call the **same** `deploy-terraform.yaml`. Nobody duplicates the init/plan/apply logic.

In a real org, the reusable workflow lives in a **separate repo** with git tags:

```yaml
# What it looks like today (same repo — demo):
uses: ./.github/workflows/deploy-terraform.yaml

# What it looks like in production (separate repo — versioned):
uses: contoso/shared-workflows/.github/workflows/deploy-terraform.yaml@v1.0
```

### Who Owns What — Summary

| File | Who Writes It | What It Does |
|---|---|---|
| `deploy-apim-terraform.yaml` | Product team | "Deploy dev then prod when terraform/ changes" — 4 job definitions, zero Terraform logic |
| `deploy-terraform.yaml` | Platform team | "Given an environment and tfvars, run init → plan → apply" — the actual Terraform execution |
| `main.tf` | Product team | "Use the shared module to deploy Orders API" — calls `module "orders_api"` |
| `modules/apim-api/` | Platform team | "Here's how every API must be deployed" — API + policy + product + subscription |
| `dev.tfvars` / `prod.tfvars` | Product team | "Here are my env-specific values" — APIM name, backend URL, etc. |
| `api_specs/orders-api.yaml` | Product team | "Here's my API definition" — read by Terraform via `file()` |
| `policies/api-policy.xml` | Product team | "Here's my API policy" — read by Terraform via `file()` |

### Required GitHub Configuration

For the workflows to run, configure these in **Settings → Environments**:

**Environments:**

| Environment | Secrets Needed |
|---|---|
| `dev` | `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID` |
| `prod` | Same + optionally add a **required reviewer** for approval gate |

**Repository permissions:**

- `Settings → Actions → General → Workflow permissions` → **Read and write permissions**
- The service principal needs **Contributor** role on the Azure subscription (or scoped to the resource group)

## Adding a New API

1. Create a new OpenAPI spec in `api_specs/` (e.g. `payments-api.yaml`)
2. Optionally create a policy in `policies/` (e.g. `payments-policy.xml`)
3. Add a module block in `main.tf`:

```hcl
module "payments_api" {
  source = "./modules/apim-api"

  apim_name        = azurerm_api_management.apim.name
  resource_group_name = azurerm_resource_group.rg.name
  api_name         = "payments-api"
  api_display_name = "Payments API"
  api_path         = "payments"
  openapi_spec     = file("${path.module}/api_specs/payments-api.yaml")
  policy_xml       = file("${path.module}/policies/payments-policy.xml")
  backend_url      = var.payments_backend_url
}
```

4. Run `terraform plan` → `terraform apply`. Done. Same naming, same product, same subscription structure.

## State Management

This demo uses **local state** (`terraform.tfstate` file on disk). This is fine for a single developer.

**For teams**, use a remote backend in Azure Storage:

```hcl
backend "azurerm" {
  resource_group_name  = "rg-terraform-state"
  storage_account_name = "tfstateapim"
  container_name       = "tfstate"
  key                  = "apim-dev.tfstate"
}
```

Benefits of remote state:
- State is shared across the team
- State locking prevents concurrent `apply` conflicts
- State is backed up and versioned
- CI/CD pipelines can access it

## What the Shared Module Enforces

The `modules/apim-api/` module guarantees that **every API** deployed by any team gets:

| Standard | How It's Enforced |
|---|---|
| **Naming convention** | `api_name` must be lowercase alphanumeric with hyphens (validated) |
| **API versioning** | Version set + version are always created |
| **HTTPS only** | `protocols = ["https"]` hardcoded in module |
| **Product per API** | Product is always created and API is always linked |
| **Subscription required** | `subscription_required = true` hardcoded |
| **Active subscription** | Subscription is automatically created in `active` state |
| **Policies** | Optional but encouraged — pass `policy_xml` to apply |

Teams **cannot skip** these standards because the module creates them automatically.

## Why Are There Two Deploy Workflows?

This repo has **two separate deploy workflows**. They are **two completely different approaches** — you'd use one OR the other, not both. They exist in the same repo because this is a workshop showing different patterns.

| | `deploy-apim.yml` (Simple CLI) | `deploy-apim-terraform.yaml` (Terraform) |
|---|---|---|
| **How it deploys** | `az apim api import` | `terraform apply` |
| **What it deploys** | API definition ONLY (from `openapi.yaml`) | EVERYTHING — API + policies + products + subscriptions + backends |
| **State tracking** | None | `.tfstate` file |
| **Drift detection** | None | `terraform plan` shows drift |
| **Standards enforcement** | None — you manage everything manually | Shared module enforces naming, products, subscriptions |
| **Best for** | Quick demo of "OpenAPI in code" approach | Enterprise pattern with full governance |

**In a real project, pick one.** For enterprise customers, use the Terraform approach.

## Developer Guide: How to Add a New API

### Step 1: Create the OpenAPI spec

Create a new file in `api_specs/`:

```yaml
# terraform/api_specs/payments-api.yaml
openapi: "3.0.1"
info:
  title: Payments API
  version: "1.0.0"
paths:
  /payments:
    get:
      operationId: getPayments
      summary: List payments
      responses:
        "200":
          description: OK
    post:
      operationId: createPayment
      summary: Create payment
      requestBody:
        required: true
        content:
          application/json:
            schema:
              type: object
              properties:
                amount:
                  type: number
                currency:
                  type: string
      responses:
        "201":
          description: Created
```

### Step 2: Create a policy (optional)

Copy the existing policy or create a new one:

```bash
cp terraform/policies/api-policy.xml terraform/policies/payments-policy.xml
```

Edit `payments-policy.xml` if you want different rate limits, CORS rules, etc.

### Step 3: Add the module block to `main.tf`

Open `terraform/main.tf` and add a new module block — this is the only Terraform code you write:

```hcl
module "payments_api" {
  source = "./modules/apim-api"

  apim_name           = azurerm_api_management.apim.name
  resource_group_name = azurerm_resource_group.rg.name
  api_name            = "payments-api"
  api_display_name    = "Payments API"
  api_path            = "payments"
  api_version         = "v1"
  openapi_spec        = file("${path.module}/api_specs/payments-api.yaml")
  policy_xml          = file("${path.module}/policies/payments-policy.xml")
  backend_url         = var.backend_url
}
```

The module automatically creates: version set, product, product-API link, subscription, and backend — all following the same naming conventions and standards as every other API.

### Step 4: Push and deploy

```bash
git add .
git commit -m "Add Payments API"
git push
```

Then go to **GitHub → Actions → Deploy APIM (Terraform) → Run workflow**.

The workflow deploys to dev first, then prod. Both environments get the new API with all standards applied automatically.

### What You Get After Deploying

For every API you add via the module, you automatically get:

| Resource | Auto-created Name |
|---|---|
| API | `payments-api` (versioned as v1) |
| Version Set | `payments-api-version-set` |
| Product | `payments-api-product` (published, subscription required) |
| Product-API link | API associated with its product |
| Subscription | `Payments API Subscription` (active, scoped to API) |
| Backend | `payments-api-backend` (if `backend_url` provided) |
| Policy | Applied from `payments-policy.xml` (if `policy_xml` provided) |

**That's it.** Three files (spec, policy, module block) and one workflow run. Same standards as every other team.

## Authentication: GitHub to Azure

There are **two ways** for GitHub Actions to authenticate to Azure. This repo uses both.

### Method 1: Client Secret (used by APIOps Extractor/Publisher)

A client secret is essentially a **password** for the service principal. You store it in GitHub Secrets and the workflow sends it to Azure.

```
GitHub                                    Azure
──────                                    ─────
Stores in secrets:
  AZURE_CLIENT_ID         ──────────┐
  AZURE_CLIENT_SECRET     ──────────┤──▶ "Here's my ID and password"
  AZURE_TENANT_ID         ──────────┘         │
                                              ▼
                                     Azure AD validates
                                     the client secret
                                              │
                                              ▼
                                     ✅ Authenticated
```

**How to set it up:**

1. Create an App Registration (Service Principal) in Azure AD
2. Go to **Certificates & secrets → Client secrets → New client secret**
3. Copy the secret value
4. Store `AZURE_CLIENT_ID`, `AZURE_CLIENT_SECRET`, `AZURE_TENANT_ID` in GitHub Secrets

**Used by** (in this repo): `run-extractor.yaml`, `run-publisher-with-env.yaml`

```yaml
# How it looks in the workflow:
env:
  AZURE_CLIENT_ID: ${{ secrets.AZURE_CLIENT_ID }}
  AZURE_CLIENT_SECRET: ${{ secrets.AZURE_CLIENT_SECRET }}
  AZURE_TENANT_ID: ${{ secrets.AZURE_TENANT_ID }}
```

### Method 2: OIDC / Federated Credentials (used by Terraform workflows) — RECOMMENDED

No password is stored anywhere. Instead, GitHub generates a **short-lived token** and Azure validates it against a **federated identity credential** configured on the App Registration.

```
GitHub                                    Azure
──────                                    ─────
Stores in secrets:
  AZURE_CLIENT_ID         ──────────┐
  AZURE_TENANT_ID         ──────────┤
  (NO secret needed!)               │
                                    │
GitHub generates a short-lived      │
OIDC token that says:               │
  "I am repo:rajata07/api_ops_demo  │
   environment:dev"                 │
         │                          │
         ▼                          │
  Token sent to Azure  ◀────────────┘
         │
         ▼
  Azure checks: "Does the App Registration
  have a federated credential matching
  repo:rajata07/api_ops_demo:environment:dev?"
         │
         ▼
  ✅ Match found → Authenticated (no password needed)
```

**How to set it up:**

1. Create an App Registration (same as Method 1 — can reuse `apiopslab`)
2. Go to **Certificates & secrets → Federated credentials → Add credential**
3. Select **GitHub Actions deploying Azure resources**
4. Add a credential for each trigger type (see table below)
5. Store only `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID` in GitHub (no secret!)
6. The workflow must have `permissions: id-token: write`

**Used by** (in this repo): `deploy-terraform.yaml`, `deploy-apim-terraform.yaml`, `deploy-apim.yml`

```yaml
# How it looks in the workflow:
- uses: azure/login@v2
  with:
    client-id: ${{ secrets.AZURE_CLIENT_ID }}
    tenant-id: ${{ secrets.AZURE_TENANT_ID }}
    subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}
    # No client-secret — OIDC handles it
```

### Comparison

| | Client Secret (Method 1) | OIDC / Federated (Method 2) |
|---|---|---|
| **What's stored in GitHub** | Client ID + **Secret** + Tenant ID | Client ID + Tenant ID (**no secret**) |
| **What authenticates** | A password (secret) | A short-lived OIDC token |
| **Token lifetime** | Months/years (until secret expires) | Minutes |
| **Secret rotation needed** | Yes — must rotate before expiry | No |
| **If GitHub secrets are leaked** | Attacker has full access | Attacker has nothing usable |
| **Setup complexity** | Simpler — just create a secret | Must add federated credentials per branch/env |
| **Recommended by Microsoft** | Legacy approach | **Yes — recommended** |

### Federated Credentials You Need

Each GitHub trigger type generates a different OIDC subject. You need a federated credential for each:

| Credential Name | Entity Type | Value | Why |
|---|---|---|---|
| `github-branch-dev` | Branch | `dev` | Workflows triggered by push to `dev` branch |
| `github-branch-main` | Branch | `main` | Workflows triggered by push to `main` branch |
| `github-env-dev` | Environment | `dev` | Workflows with `environment: dev` (Terraform, extractor, publisher) |
| `github-env-prod` | Environment | `prod` | Workflows with `environment: prod` (Terraform, publisher) |
| `github-pr` | Pull Request | — | Workflows triggered by pull requests (Terraform plan) |

**All credentials use the same settings:**

| Field | Value |
|---|---|
| Organization | Your GitHub username or org |
| Repository | Your repo name |
| Audience | `api://AzureADTokenExchange` (default) |

### Which Method Should You Use?

| Scenario | Recommendation |
|---|---|
| New project, starting fresh | **OIDC (Method 2)** — no secrets to manage |
| Existing workflows using client secrets | Migrate to OIDC when you can, but no rush |
| APIOps extractor/publisher | Currently requires `AZURE_CLIENT_SECRET` in env vars — use Method 1 |
| Terraform, Azure CLI, `azure/login@v2` | **OIDC (Method 2)** — fully supported |
| Strict security / compliance requirements | **OIDC (Method 2)** — no long-lived credentials |

### Service Principal Permissions

Regardless of which method you use, the service principal needs the **Contributor** role on the subscription (or scoped to specific resource groups):

```bash
az role assignment create \
  --assignee <AZURE_CLIENT_ID> \
  --role "Contributor" \
  --scope "/subscriptions/<SUBSCRIPTION_ID>"
```

## Troubleshooting

| Issue | Solution |
|---|---|
| `apim_name` already taken | APIM names are globally unique — add a random suffix |
| Deployment takes 30+ minutes | You're using a classic SKU (`Developer_1`). Switch to `BasicV2_1` in your `.tfvars` — deploys in ~5 minutes |
| `terraform plan` shows unexpected changes | Someone modified APIM in the portal. Apply to sync back to code |
| Authentication error | Run `az login` and ensure your account has Contributor role on the subscription |
