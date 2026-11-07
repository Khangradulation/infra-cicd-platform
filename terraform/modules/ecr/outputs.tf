output "repository_name" {
  description = "Repository name."
  value       = aws_ecr_repository.this.name
}

output "repository_arn" {
  description = "Repository ARN (scope IAM push/pull policies to this)."
  value       = aws_ecr_repository.this.arn
}

output "repository_url" {
  description = "Registry URL without tag, e.g. <account>.dkr.ecr.<region>.amazonaws.com/icp/app."
  value       = aws_ecr_repository.this.repository_url
}
