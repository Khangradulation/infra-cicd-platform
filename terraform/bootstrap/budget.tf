# Cost guard-rail: email when this project's spend reaches 50% / 100% of a
# small monthly budget (or is forecast to exceed it). Scoped to resources
# tagged Project=infra-cicd-platform so other workloads in the same account
# don't trigger it. AWS Budgets: first 2 budgets per account are free.
#
# The tag filter only counts costs once "Project" is an ACTIVE cost-allocation
# tag. AWS only lets you activate it after it has seen the tag on a resource
# (up to 24h after the first apply), so activation is a second, optional step:
# set activate_cost_allocation_tag = true and apply again the next day.

resource "aws_ce_cost_allocation_tag" "project" {
  count = var.activate_cost_allocation_tag ? 1 : 0

  tag_key = "Project"
  status  = "Active"
}

resource "aws_budgets_budget" "project" {
  count = length(var.budget_alert_emails) > 0 ? 1 : 0

  name         = "${var.name_prefix}-monthly-cost"
  budget_type  = "COST"
  limit_amount = tostring(var.monthly_budget_usd)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  # Tag-scoped only when the Project tag can be active. A linked account in an
  # AWS Organization can't activate cost-allocation tags itself; in a dedicated
  # project account set budget_scope_to_project_tag = false to budget all spend.
  dynamic "cost_filter" {
    for_each = var.budget_scope_to_project_tag ? [1] : []
    content {
      name   = "TagKeyValue"
      values = ["user:Project$infra-cicd-platform"]
    }
  }

  dynamic "notification" {
    for_each = [
      { type = "ACTUAL", threshold = 50 },
      { type = "ACTUAL", threshold = 80 },
      { type = "ACTUAL", threshold = 100 },
      { type = "FORECASTED", threshold = 100 },
    ]
    content {
      comparison_operator        = "GREATER_THAN"
      threshold                  = notification.value.threshold
      threshold_type             = "PERCENTAGE"
      notification_type          = notification.value.type
      subscriber_email_addresses = var.budget_alert_emails
    }
  }
}
