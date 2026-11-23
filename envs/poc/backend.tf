# Remote state in the GCS bucket created by ../../bootstrap: shared, versioned
# and locked, so CI and people never overwrite each other's changes.
#
# The bucket name is passed at init time, so it isn't hard-coded:
#
#   terraform init -backend-config="bucket=giveplease-ai-reports-tfstate"
#
# GitHub Actions passes it from the TF_STATE_BUCKET repository variable.
terraform {
  backend "gcs" {
    prefix = "landing-zone/poc"
  }
}
