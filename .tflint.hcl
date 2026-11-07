# TFLint configuration (TFLint 0.65.x). Used by `make tflint` and CI.
config {
  call_module_type = "local"
  force            = false
}

plugin "terraform" {
  enabled = true
  preset  = "all"
}

plugin "aws" {
  enabled = true
  version = "0.50.0"
  source  = "github.com/terraform-linters/tflint-ruleset-aws"
}

# Examples and tests intentionally keep everything in one file.
rule "terraform_standard_module_structure" {
  enabled = false
}

# Environment roots pin with "~> 1.17.0"; modules accept a range on purpose.
rule "terraform_required_version" {
  enabled = true
}
