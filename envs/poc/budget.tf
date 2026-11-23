data "google_project" "this" {
  project_id = var.project_id
}

# Optional monthly budget with alerts at 50%, 90% and 100% of actual spend,
# and 100% of forecast spend. Alerts go to the billing account's admins.
resource "google_billing_budget" "landing_zone" {
  count = var.enable_budget ? 1 : 0

  billing_account = var.billing_account_id
  display_name    = "${var.project_id} PoC budget"

  budget_filter {
    projects = ["projects/${data.google_project.this.number}"]
  }

  amount {
    specified_amount {
      currency_code = var.budget_currency
      units         = tostring(floor(var.budget_amount))
    }
  }

  threshold_rules {
    threshold_percent = 0.5
  }
  threshold_rules {
    threshold_percent = 0.9
  }
  threshold_rules {
    threshold_percent = 1.0
  }
  threshold_rules {
    threshold_percent = 1.0
    spend_basis       = "FORECASTED_SPEND"
  }

  lifecycle {
    precondition {
      condition     = var.billing_account_id != null
      error_message = "Set billing_account_id when enable_budget is true."
    }
  }

  depends_on = [google_project_service.required]
}
