output "state_bucket_name" {
  description = "Terraform state bucket. Set as GitHub repository variable TF_STATE_BUCKET."
  value       = aws_s3_bucket.state.id
}

output "state_bucket_arn" {
  description = "Terraform state bucket ARN."
  value       = aws_s3_bucket.state.arn
}

output "state_kms_key_arn" {
  description = "KMS key encrypting state. Set as GitHub repository variable TF_STATE_KMS_KEY_ARN."
  value       = aws_kms_key.state.arn
}

output "region" {
  description = "Region of the state bucket. Set as GitHub repository variable AWS_REGION."
  value       = local.region
}

output "backend_hcl" {
  description = "Contents for terraform/environments/<env>/backend.hcl (scripts/write-backend-config.sh writes these for you)."
  value       = <<-EOT
    bucket     = "${aws_s3_bucket.state.id}"
    region     = "${local.region}"
    kms_key_id = "${aws_kms_key.state.arn}"
  EOT
}
