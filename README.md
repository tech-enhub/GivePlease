# GivePlease data landing zone (Terraform)

Creates the BigQuery PoC data landing zone in the existing project `giveplease-ai-reports`, in `asia-southeast1` (Singapore). It builds the same resources as the console runbook ("Landing zone" tab of the Natural-Language Analytics doc), so use **either** the runbook **or** this code, not both. If the resources already exist from the console, import them first (see below).

## Layout

```
terraform/                          (in tech-enhub/giveplease; .github/ and pre-commit sit at the repository root)
├── bootstrap/                      run once by a person: state bucket, Workload Identity Federation, CI service accounts
├── modules/                        reusable building blocks, no provider or backend config
│   ├── gcs-landing-bucket/         private bucket: uniform access, public access blocked, delete-after-N-days rule
│   ├── bigquery-datasets/          datasets in one location, plus tables from JSON schemas
│   └── service-account/            service account (no key) with project-, bucket- and dataset-level roles
├── envs/
│   └── poc/                        root module for the PoC: backend, provider, APIs, module calls, budget
├── .tflint.hcl  .checkov.yml  .terraform-version  .gitignore
└── README.md

Repository root:
├── .github/
│   ├── workflows/terraform-plan.yml    pull requests: fmt, validate, tflint, Checkov, plan, plan comment
│   ├── workflows/terraform-apply.yml   merge to main (or manual): plan + apply after approval
│   ├── workflows/pr-source-branch.yml  pull requests into main must come from the terraform branch
│   ├── dependabot.yml                  weekly updates for actions and the Google provider
│   └── pull_request_template.md
├── .pre-commit-config.yaml  .editorconfig  README.md
└── terraform/
```

Another environment later (for example `envs/prod`) is a copy of `envs/poc` with its own values and state prefix; the modules stay the same.

## What `envs/poc` creates (14 resources with defaults)

| Where | Resources |
| --- | --- |
| `apis.tf` | BigQuery, BigQuery Storage, Cloud Storage and IAM APIs (plus the Billing Budget API when a budget is enabled). Never switched off on destroy. |
| `module.landing_bucket` | `<project_id>-landing`: Standard class, uniform access, public access prevention enforced, files deleted after 30 days, no versioning, `force_destroy = false`. |
| `module.bigquery` | Datasets `gp_raw`, `gp_audit`, `gp_curated` in asia-southeast1, and `gp_audit.load_log` (partitioned by day on `loaded_at`, deletion protection on). |
| `module.loader` | Service account `gp-loader` (no key): BigQuery Job User on the project, Storage Object Admin on the bucket, BigQuery Data Editor on `gp_raw` and `gp_audit` only. |
| `main.tf` | Optional read access for a data-admins group. |
| `budget.tf` | Optional monthly budget with alerts at 50%, 90%, 100% and 100% forecast. Off by default. |

## Practices followed

- **Modules for reuse, a thin root per environment.** Modules declare only a minimum provider version; the root pins the exact range and owns the backend and provider settings.
- **Pinned versions:** Terraform `>= 1.5`, Google provider `>= 6.14, < 8` in the root. Commit `.terraform.lock.hcl` after the first `init`.
- **Remote state** in a separate, versioned GCS bucket created by `bootstrap/`, prefix `landing-zone/poc`, never in the landing bucket.
- **Keyless CI:** GitHub Actions uses Workload Identity Federation, with separate read-only (plan) and write (apply) identities, and apply gated by a protected environment.
- **Checks on every pull request:** `terraform fmt`, `validate`, tflint (with the Google ruleset) and a Checkov security scan.
- **Validated inputs** in both the root and the modules: the region can only be asia-southeast1; IDs, emails and names are checked before anything is called.
- **Least privilege:** the loader gets resource-level roles, not project-wide data roles, and no key file.
- **Non-authoritative IAM** (`*_iam_member`), so access granted outside Terraform isn't removed.
- **Safe deletes:** no force-destroy on the bucket, no delete-contents on datasets, deletion protection on the load log.
- **Consistent labels** on every resource through provider `default_labels`: `project`, `environment`, `component`, `managed_by`.
- **`for_each` with stable keys** (never `count` on lists), so adding a dataset or role doesn't recreate the others.

## CI/CD and authentication (Workload Identity Federation)

GitHub Actions authenticates to Google Cloud with **Workload Identity Federation**: each run gets a short-lived token from GitHub's OIDC issuer and exchanges it for short-lived Google credentials. There are **no service account keys** anywhere.

| Identity | Used by | Can do | Who can use it |
| --- | --- | --- | --- |
| `tf-plan@<project>` | `terraform-plan.yml` on pull requests | Read resources and IAM, read and lock state | Any workflow in the configured repository |
| `tf-apply@<project>` | `terraform-apply.yml` after merge | Create and change the landing zone; project IAM limited to granting BigQuery Job User | Only jobs running in the protected GitHub environment `poc` |

The Workload Identity provider also rejects tokens from any other repository (`attribute_condition`), so a fork or another repo in the same organisation can't use it.

### One-time setup

1. **Billing linked** to `giveplease-ai-reports`.
2. **Bootstrap** (as tech@enhub.ai, in Cloud Shell):
   ```bash
   cd terraform/bootstrap
   cp terraform.tfvars.example terraform.tfvars    # github_repository is already tech-enhub/giveplease
   terraform init
   terraform plan -out=tfplan && terraform apply tfplan
   terraform output github_variables
   ```
   Then move the bootstrap state into the bucket (steps in `bootstrap/backend.tf`).
3. **GitHub repository variables** (Settings > Secrets and variables > Actions > Variables): `GCP_PROJECT_ID`, `GCP_WIF_PROVIDER`, `GCP_PLAN_SA`, `GCP_APPLY_SA`, `TF_STATE_BUCKET`, from the bootstrap output. None of these are secrets.
4. **GitHub environment `poc`** (Settings > Environments): add required reviewers, and limit deployment branches to `main`.
5. **Branch protection on `main`:** require a pull request, one approval, and these checks to pass: `Source branch is terraform`, `Format, lint and security scan`, `Plan (poc)`.

### Day to day

All changes go through one branch, `terraform`. Pull requests into `main` from any other branch fail the `pr-source-branch` check.

1. Commit changes to the `terraform` branch and open a pull request from `terraform` into `main`.
2. `terraform-plan` runs fmt, validate, tflint and Checkov, then posts the plan as a comment. Review it; screenshot it for the PoC documentation.
3. Merge. `terraform-apply` waits for an approver on the `poc` environment, then plans and applies.

Run the same checks locally with `pre-commit install` (see `.pre-commit-config.yaml`).

## Running by hand (without CI)

### Before you run it

1. **Billing must be linked** to `giveplease-ai-reports`.
2. Terraform 1.5 or later and `gcloud`, signed in as tech@enhub.ai. Cloud Shell has both.
3. The state bucket exists (created by `bootstrap/`).

### Run

```bash
cd terraform/envs/poc
cp terraform.tfvars.example terraform.tfvars        # edit if needed
gcloud auth application-default login                # skip in Cloud Shell
terraform init -backend-config="bucket=giveplease-ai-reports-tfstate"
terraform fmt -recursive -check ../..
terraform validate
terraform plan -out=tfplan                           # review: expect 14 resources to add
terraform apply tfplan
```

Screenshot the plan summary and the apply output for the PoC documentation, then check the resources with step 9 of the runbook.

## If the resources were already created in the console

Don't apply over them: Terraform would fail with "already exists". Add `envs/poc/imports.tf` like this, run `terraform plan`, and check it shows no changes to these resources:

```hcl
import {
  to = module.landing_bucket.google_storage_bucket.this
  id = "giveplease-ai-reports-landing"
}
import {
  to = module.bigquery.google_bigquery_dataset.this["gp_raw"]
  id = "projects/giveplease-ai-reports/datasets/gp_raw"
}
import {
  to = module.bigquery.google_bigquery_dataset.this["gp_audit"]
  id = "projects/giveplease-ai-reports/datasets/gp_audit"
}
import {
  to = module.bigquery.google_bigquery_dataset.this["gp_curated"]
  id = "projects/giveplease-ai-reports/datasets/gp_curated"
}
import {
  to = module.bigquery.google_bigquery_table.this["load_log"]
  id = "projects/giveplease-ai-reports/datasets/gp_audit/tables/load_log"
}
import {
  to = module.loader.google_service_account.this
  id = "projects/giveplease-ai-reports/serviceAccounts/gp-loader@giveplease-ai-reports.iam.gserviceaccount.com"
}
```

IAM members and APIs don't need importing; Terraform adds them again without changing anything.

## Removing it

`terraform destroy` refuses while the bucket holds files, a dataset holds tables, or the load log has deletion protection. That is deliberate. To remove everything, set `deletion_protection = false` for `load_log` in `envs/poc/locals.tf` and apply, then empty the bucket and datasets, then destroy. Do this only when your lead asks.
