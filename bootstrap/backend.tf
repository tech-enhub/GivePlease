# The bootstrap creates the state bucket, so its first run uses local state.
# After the first apply, move its state into the bucket so it isn't lost:
#
#   1. Uncomment the block below.
#   2. terraform init -migrate-state -backend-config="bucket=giveplease-ai-reports-tfstate"
#   3. Delete the local terraform.tfstate files once the migration succeeds.
#
terraform {
  backend "gcs" {
    prefix = "bootstrap"
  }
}
