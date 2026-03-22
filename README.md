# APIOps Demo - Azure API Management CI/CD

This repository implements [APIOps](https://github.com/Azure/APIOps) for Azure API Management (APIM). APIOps applies GitOps principles to API deployment — your APIM configuration is stored as code in this repository and automatically synchronized to Azure through CI/CD pipelines.

## Table of Contents

- [Repository Structure](#repository-structure)
- [How It Works — End-to-End Flow](#how-it-works--end-to-end-flow)
- [Workflows](#workflows)
  - [1. Run - Extractor (`run-extractor.yaml`)](#1-run---extractor-run-extractoryaml)
  - [2. Run - Publisher (`run-publisher.yaml`)](#2-run---publisher-run-publisheryaml)
  - [3. Run Publisher with Environment (`run-publisher-with-env.yaml`)](#3-run-publisher-with-environment-run-publisher-with-envyaml)
- [Configuration Files](#configuration-files)
  - [Extractor Configuration (`configuration.extractor.yaml`)](#extractor-configuration-configurationextractoryaml)
  - [Environment Configuration (`configuration.prod.yaml`)](#environment-configuration-configurationprodyaml)
- [API Specification Formats](#api-specification-formats)
- [What is `apiops_release_version`?](#what-is-apiops_release_version)
- [GitHub Secrets and Environments](#github-secrets-and-environments)
- [Deployment Flow: Dev to Prod](#deployment-flow-dev-to-prod)
- [References](#references)

---

## Repository Structure

```
.
├── .github/workflows/
│   ├── run-extractor.yaml              # Extracts APIM config from Azure → Git
│   ├── run-publisher.yaml              # Orchestrates publishing from Git → Azure
│   └── run-publisher-with-env.yaml     # Reusable workflow called by run-publisher.yaml
├── apimartifacts/                      # Extracted APIM artifacts (APIs, policies, backends, etc.)
├── configuration.extractor.yaml        # Controls which resources the extractor pulls
├── configuration.prod.yaml             # Environment-specific overrides for production
└── README.md
```

### `apimartifacts/` Directory

This folder contains the APIM artifacts extracted from your Azure APIM instance. It includes APIs, policies, diagnostics, loggers, named values, products, subscriptions, and groups. **Do not manually edit files here unless you know what you are doing** — this folder is populated by the extractor pipeline and consumed by the publisher pipeline.

---

## How It Works — End-to-End Flow

APIOps uses two tools — the **Extractor** and the **Publisher** — to manage the lifecycle of your API configurations:

```
┌─────────────────────────────────────────────────────────────────────┐
│                        APIOps Workflow                               │
│                                                                     │
│  1. EXTRACT (manual trigger)                                        │
│     Azure APIM (Dev) ──→ Extractor ──→ Pull Request with artifacts  │
│                                                                     │
│  2. REVIEW & MERGE                                                  │
│     Developer reviews PR ──→ Merges to main                         │
│                                                                     │
│  3. PUBLISH (automatic on merge to main)                            │
│     main branch ──→ Publisher ──→ Dev APIM ──→ Prod APIM            │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

**Step-by-step:**

1. **Extract**: A developer manually triggers the extractor workflow. It connects to the source (dev) APIM instance, pulls down the current configuration, and creates a **Pull Request** with the artifacts.
2. **Review**: The team reviews the PR. You can make changes to APIs, policies, or configurations directly in the PR before merging.
3. **Merge**: Once the PR is merged into `main`, the publisher workflow **automatically triggers**.
4. **Publish to Dev**: The publisher first deploys changes to the **dev** APIM instance.
5. **Publish to Prod**: After the dev deployment succeeds, the publisher promotes the changes to **prod** (requires environment approval if configured).

> **Important**: The publisher pipeline is **not** automatically triggered by the extractor. The extractor only creates a PR. The publisher triggers when that PR (or any other change) is **merged to `main`**.

---

## Workflows

### 1. Run - Extractor (`run-extractor.yaml`)

**Purpose**: Extracts the current APIM configuration from Azure and creates a Pull Request with the artifacts in this repository.

| Property | Value |
|---|---|
| **Trigger** | Manual only (`workflow_dispatch`) |
| **Environment** | `dev` |
| **Output** | A Pull Request containing extracted artifacts in `apimartifacts/` |

**How to run it:**

1. Go to **Actions** → **Run - Extractor**
2. Click **Run workflow**
3. Choose your inputs:

| Input | Description |
|---|---|
| `CONFIGURATION_YAML_PATH` | Choose **"Extract All APIs"** to extract everything, or **"configuration.extractor.yaml"** to extract only the resources listed in the config file |
| `API_SPECIFICATION_FORMAT` | The format for extracted API specifications (see [API Specification Formats](#api-specification-formats)) |

**What it does:**

1. Checks out the repository
2. Downloads the APIOps extractor tool from the [Azure/APIOps](https://github.com/Azure/APIOps) releases
3. Connects to your APIM instance using the service principal credentials stored in GitHub secrets
4. Extracts APIM artifacts (APIs, policies, named values, backends, loggers, etc.) into the `apimartifacts/` folder
5. Uploads the artifacts as a GitHub Actions artifact
6. Creates a **Pull Request** with the changes for review

**Example**: If you have made changes to APIs directly in the Azure Portal and want to sync those changes back into Git, run the extractor.

---

### 2. Run - Publisher (`run-publisher.yaml`)

**Purpose**: Orchestrates the deployment of APIM artifacts from this repository to Azure APIM instances (dev, then prod).

| Property | Value |
|---|---|
| **Trigger** | Automatic on push to `main` **+ Manual** (`workflow_dispatch`) |
| **Environments** | `dev` → `prod` (sequential) |

**Automatic trigger**: Any push to the `main` branch (including merged PRs from the extractor) automatically triggers this workflow.

**Manual trigger**: Go to **Actions** → **Run - Publisher** → **Run workflow** and choose:

| Input | Options | Description |
|---|---|---|
| `COMMIT_ID_CHOICE` | `publish-artifacts-in-last-commit` (default) | Only publishes artifacts that changed in the last commit |
| | `publish-all-artifacts-in-repo` | Force-publishes all artifacts in `apimartifacts/` — useful after a build failure or to ensure everything is in sync |

**What it does:**

This workflow calls the reusable `run-publisher-with-env.yaml` workflow for each environment. The deployment jobs are structured as follows:

```
get-commit
    │
    ├── Push-Changes-To-APIM-Dev      (always runs first)
    │       │
    │       └── Push-Changes-To-APIM-Prod   (runs after dev succeeds)
    │
    └── (or if "publish-all-artifacts-in-repo" was chosen, a separate path without commit ID)
```

**Key behavior:**
- **Dev deployment** does **not** use a configuration YAML — it publishes artifacts as-is
- **Prod deployment** uses `configuration.prod.yaml` to apply environment-specific overrides (e.g., different backend URLs, service names, named values)
- **Prod waits for Dev** — the prod job has a `needs` dependency on the dev job, so it only runs after dev succeeds
- If you have configured [environment protection rules](https://docs.github.com/en/actions/deployment/targeting-different-environments/using-environments-for-deployment#deployment-protection-rules) on the `prod` environment in GitHub, you will be prompted to approve the deployment before it proceeds to prod

---

### 3. Run Publisher with Environment (`run-publisher-with-env.yaml`)

**Purpose**: A **reusable workflow** (called by `run-publisher.yaml`) that performs the actual publishing to a specific APIM environment.

| Property | Value |
|---|---|
| **Trigger** | `workflow_call` only (cannot be triggered directly) |
| **Called by** | `run-publisher.yaml` |

**Inputs it accepts:**

| Input | Required | Description |
|---|---|---|
| `API_MANAGEMENT_ENVIRONMENT` | Yes | Target environment name (e.g., `dev`, `prod`) — must match a GitHub Environment |
| `CONFIGURATION_YAML_PATH` | No | Path to the environment config YAML (e.g., `configuration.prod.yaml`). If empty, no overrides are applied |
| `COMMIT_ID` | No | If provided, only changed artifacts are published. If empty, all artifacts are published |
| `API_MANAGEMENT_SERVICE_OUTPUT_FOLDER_PATH` | Yes | Path to the artifacts folder (`apimartifacts`) |

**What it does:**

1. Checks out the repository
2. Runs [Spectral](https://stoplight.io/open-source/spectral) API linting on the extracted API specs
3. Performs **secret token substitution** in `configuration.{env}.yaml` — replaces `{#tokenName#}` placeholders with actual secret values from GitHub Secrets
4. Downloads the APIOps publisher tool
5. Publishes artifacts to the target APIM instance

The workflow has four conditional steps to handle all combinations:

| Condition | Behavior |
|---|---|
| No config YAML + has commit ID | Publishes only changed artifacts, no overrides |
| No config YAML + no commit ID | Publishes all artifacts, no overrides |
| Has config YAML + has commit ID | Publishes only changed artifacts with overrides |
| Has config YAML + no commit ID | Publishes all artifacts with overrides |

---

## Configuration Files

### Extractor Configuration (`configuration.extractor.yaml`)

Controls **which** APIM resources the extractor should pull. If you select "Extract All APIs" when running the extractor, this file is ignored and everything is extracted.

```yaml
apiNames:                    # Which APIs to extract
  - mock-api-operation

backendNames:                # Which backends to extract (empty = none)

diagnosticNames:             # Which diagnostic settings to extract
  - applicationinsights
  - azuremonitor

loggerNames:                 # Which loggers to extract
  - azuremonitor
  - app-insights

namedValueNames:             # Which named values to extract
  - 69b40de47b201b1da8d5d6a9

productNames:                # Which products to extract
  - developers-x-team

subscriptionNames:           # Which subscriptions to extract
  - master
  - 69c040597e3c4c3fade4d551

tagNames:                    # Which tags to extract (empty = none)

policyFragmentNames:         # Which policy fragments to extract (empty = none)
```

Use this file to limit extraction to specific resources — useful when your APIM instance has many APIs and you only want to manage a subset via APIOps.

### Environment Configuration (`configuration.prod.yaml`)

Provides **overrides** when publishing to the production environment. This allows you to change values like the APIM service name, backend URLs, named values, logger configurations, etc.

```yaml
apimServiceName: contiworkshopapimprod    # Target APIM instance for prod
namedValues:                               # Override named values for prod
loggers:                                   # Override logger configs for prod
diagnostics:                               # Override diagnostic settings for prod
backends:                                  # Override backend URLs for prod
apis:                                      # Override API-level settings for prod
```

For a full example with all override options, see the [sample configuration file](https://github.com/Azure/apiops/blob/main/configuration.prod.yaml) in the APIOps repository.

**Token substitution**: If you have secrets that need to be injected at deployment time, use the `{#tokenName#}` syntax in the config file. For example:

```yaml
namedValues:
  - name: testSecret
    properties:
      displayName: testSecret
      value: "{#testSecretValue#}"
```

The publisher workflow replaces `{#testSecretValue#}` with the value of the `testSecretValue` GitHub secret at runtime.

---

## API Specification Formats

When running the extractor, you choose an API specification format. This determines how your API definitions are exported:

| Format | Description | When to Use |
|---|---|---|
| **OpenAPIV3Yaml** | OpenAPI 3.0 in YAML format | **Recommended default**. Human-readable, easy to review in PRs, widely supported by modern tools |
| **OpenAPIV3Json** | OpenAPI 3.0 in JSON format | When your toolchain requires JSON (e.g., some code generators or validators). Functionally identical to OpenAPIV3Yaml |
| **OpenAPIV2Yaml** | Swagger 2.0 in YAML format | Legacy compatibility. Use only if your downstream tools require Swagger 2.0 |
| **OpenAPIV2Json** | Swagger 2.0 in JSON format | Legacy compatibility with JSON requirement. Also known as "Swagger JSON" |

**Recommendation**: Use **OpenAPIV3Yaml** unless you have a specific reason to choose another format. OpenAPI 3.0 is the current standard and YAML is easier to read and review in pull requests compared to JSON.

> **Note**: The format only affects API specification files. Other artifacts (policies, named values, loggers, etc.) are always extracted in their native format.

---

## What is `apiops_release_version`?

```yaml
env:
  apiops_release_version: v6.0.2
```

This is the version of the [APIOps Toolkit](https://github.com/Azure/APIOps/releases) used by the workflows. Both the extractor and publisher workflows download their executable binaries from the APIOps GitHub releases using this version tag.

The download URL is constructed as:
```
https://github.com/Azure/apiops/releases/download/{version}/publisher-linux-x64.zip
https://github.com/Azure/apiops/releases/download/{version}/extractor-linux-x64.zip
```

**To update**: Change the value in **both** workflow files:
- `.github/workflows/run-extractor.yaml`
- `.github/workflows/run-publisher-with-env.yaml`

Check the [APIOps Releases](https://github.com/Azure/APIOps/releases) page for the latest version.

---

## GitHub Secrets and Environments

### Environments

You need two GitHub Environments configured under **Settings → Environments**:

| Environment | Purpose |
|---|---|
| `dev` | Source environment for extraction; first deployment target for publishing |
| `prod` | Production deployment target (optionally with approval gates) |

> **Tip**: Add a [required reviewer](https://docs.github.com/en/actions/deployment/targeting-different-environments/using-environments-for-deployment#required-reviewers) on the `prod` environment to enforce manual approval before production deployments.

### Secrets (per environment)

Each environment needs these secrets:

| Secret | Description |
|---|---|
| `AZURE_CLIENT_ID` | Service principal application (client) ID |
| `AZURE_CLIENT_SECRET` | Service principal client secret |
| `AZURE_TENANT_ID` | Azure Active Directory tenant ID |
| `AZURE_SUBSCRIPTION_ID` | Azure subscription ID containing the APIM instance |
| `AZURE_RESOURCE_GROUP_NAME` | Resource group name where the APIM instance is deployed |
| `API_MANAGEMENT_SERVICE_NAME` | Name of the APIM service instance |

### Variables (optional)

| Variable | Description |
|---|---|
| `LOG_LEVEL` | Logging verbosity for the publisher/extractor (default: `Information`). Set per environment under **Settings → Environments → Environment variables** |

### Required Repository Settings

Before running the extractor, enable: **Settings → Actions → General → "Allow GitHub Actions to create and approve pull requests"**. This is needed for the extractor to create PRs automatically.

---

## Deployment Flow: Dev to Prod

Here is the complete end-to-end deployment flow:

```
                         ┌──────────────────────┐
                         │  1. Manual Trigger    │
                         │  Run - Extractor      │
                         │  (workflow_dispatch)   │
                         └──────────┬─────────────┘
                                    │
                                    ▼
                         ┌──────────────────────┐
                         │  2. Extractor pulls   │
                         │  artifacts from       │
                         │  Dev APIM instance    │
                         └──────────┬─────────────┘
                                    │
                                    ▼
                         ┌──────────────────────┐
                         │  3. PR Created        │
                         │  with extracted       │
                         │  artifacts            │
                         └──────────┬─────────────┘
                                    │
                                    ▼
                         ┌──────────────────────┐
                         │  4. Developer reviews │
                         │  and merges PR to     │
                         │  main branch          │
                         └──────────┬─────────────┘
                                    │
                                    ▼
                         ┌──────────────────────┐
                         │  5. Push to main      │
                         │  triggers Publisher   │
                         │  (automatic)          │
                         └──────────┬─────────────┘
                                    │
                                    ▼
                         ┌──────────────────────┐
                         │  6. Publisher deploys │
                         │  to DEV APIM         │
                         │  (no config overrides)│
                         └──────────┬─────────────┘
                                    │
                                    ▼
                         ┌──────────────────────────┐
                         │  7. Dev succeeds →       │
                         │  Publisher deploys to     │
                         │  PROD APIM               │
                         │  (with config overrides   │
                         │  from configuration.      │
                         │  prod.yaml)               │
                         └──────────────────────────┘
```

**Key points:**
- The **extractor** only creates a PR — it does NOT deploy anything
- The **publisher** is what deploys to APIM environments
- The publisher is triggered **automatically** when code is merged to `main`, or **manually** via workflow dispatch
- Dev is always deployed first; prod is deployed only after dev succeeds
- Prod uses `configuration.prod.yaml` for environment-specific overrides
- If environment protection rules (approval gates) are configured on the `prod` environment, a reviewer must approve before the prod deployment proceeds

---

## References

- [APIOps Toolkit (GitHub)](https://github.com/Azure/APIOps)
- [APIOps Documentation](https://azure.github.io/apiops/)
- [Extract APIM Artifacts (GitHub)](https://azure.github.io/apiops/apiops/4-extractApimArtifacts/apiops-github-3-2.html)
- [Publish APIM Artifacts (GitHub)](https://azure.github.io/apiops/apiops/5-publishApimArtifacts/apiops-github-4-2-pipeline.html)
- [Configure APIM Tools](https://azure.github.io/apiops/apiops/3-apimTools/apiops-2-2-tools-publisher.html)
- [APIOps Releases](https://github.com/Azure/APIOps/releases)
- [Azure API Management Documentation](https://learn.microsoft.com/en-us/azure/api-management/)
