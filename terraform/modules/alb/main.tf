data "aws_caller_identity" "current" {}
data "aws_elb_service_account" "current" {}

locals {
  https_enabled  = var.certificate_arn != null
  listener_ports = local.https_enabled ? [80, 443] : [80]
  ingress = {
    for pair in setproduct(var.allowed_ingress_cidrs, local.listener_ports) :
    "${pair[0]}-${pair[1]}" => { cidr = pair[0], port = pair[1] }
  }
}

# ------------------------------------------------------- Security group

resource "aws_security_group" "alb" {
  name        = "${var.name}-alb"
  description = "Ingress to ${var.name} ALB on HTTP/HTTPS only"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, { Name = "${var.name}-alb" })

  lifecycle {
    create_before_destroy = true
  }
}

# trivy:ignore:AWS-0053 Ingress CIDRs are var.allowed_ingress_cidrs (restrict per env)
resource "aws_vpc_security_group_ingress_rule" "alb" {
  for_each = local.ingress

  security_group_id = aws_security_group.alb.id
  description       = "Listener ${each.value.port} from ${each.value.cidr}"
  cidr_ipv4         = each.value.cidr
  ip_protocol       = "tcp"
  from_port         = each.value.port
  to_port           = each.value.port
}

# Egress only to the target port, only inside the VPC.
resource "aws_vpc_security_group_egress_rule" "alb_to_targets" {
  security_group_id = aws_security_group.alb.id
  description       = "Forward to targets on ${var.target_port}"
  cidr_ipv4         = var.vpc_cidr
  ip_protocol       = "tcp"
  from_port         = var.target_port
  to_port           = var.target_port
}

# ------------------------------------------------------- Load balancer

# trivy:ignore:AWS-0053 Public API by design (SEC-07: put WAF/CIDR allow-lists in front if needed)
resource "aws_lb" "this" {
  #checkov:skip=CKV2_AWS_20:Exception SEC-06: HTTP->HTTPS redirect is created whenever certificate_arn is set; no cert can be assumed
  #checkov:skip=CKV2_AWS_28:Exception SEC-07: WAF is an opt-in upgrade (~USD 5+/month per ACL); see docs/security.md
  name               = "${var.name}-alb"
  load_balancer_type = "application"
  internal           = false
  security_groups    = [aws_security_group.alb.id]
  subnets            = var.public_subnet_ids

  idle_timeout                     = var.idle_timeout
  enable_deletion_protection       = var.enable_deletion_protection
  drop_invalid_header_fields       = true
  enable_cross_zone_load_balancing = true
  desync_mitigation_mode           = "defensive"

  dynamic "access_logs" {
    for_each = var.enable_access_logs ? [1] : []
    content {
      bucket  = aws_s3_bucket.access_logs[0].id
      prefix  = var.name
      enabled = true
    }
  }

  tags = merge(var.tags, { Name = "${var.name}-alb" })

  depends_on = [aws_s3_bucket_policy.access_logs]
}

# trivy:ignore:AWS-0054 Exception SEC-08: TLS terminates at the ALB
resource "aws_lb_target_group" "app" {
  #checkov:skip=CKV_AWS_378:Exception SEC-08: TLS terminates at the ALB; ALB->task hop is inside the VPC, SG-restricted
  name                 = "${var.name}-tg"
  vpc_id               = var.vpc_id
  port                 = var.target_port
  protocol             = "HTTP"
  target_type          = "ip" # required for Fargate awsvpc networking
  deregistration_delay = var.deregistration_delay

  health_check {
    enabled             = true
    path                = var.health_check_path
    protocol            = "HTTP"
    port                = "traffic-port"
    matcher             = "200"
    interval            = var.health_check_interval
    timeout             = 5
    healthy_threshold   = var.healthy_threshold
    unhealthy_threshold = var.unhealthy_threshold
  }

  tags = merge(var.tags, { Name = "${var.name}-tg" })
}

# ------------------------------------------------------------ Listeners

# trivy:ignore:AWS-0054 Exception SEC-06: only without certificate_arn
resource "aws_lb_listener" "http_forward" {
  #checkov:skip=CKV_AWS_2:Exception SEC-06: only created when no certificate_arn is supplied; prod root warns via check block
  #checkov:skip=CKV_AWS_103:Exception SEC-06: plain-HTTP listener has no TLS policy by definition
  count = local.https_enabled ? 0 : 1

  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }

  tags = var.tags
}

resource "aws_lb_listener" "http_redirect" {
  count = local.https_enabled ? 1 : 0

  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }

  tags = var.tags
}

resource "aws_lb_listener" "https" {
  count = local.https_enabled ? 1 : 0

  load_balancer_arn = aws_lb.this.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = var.ssl_policy
  certificate_arn   = var.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }

  tags = var.tags
}

# ---------------------------------------------------- Access-log bucket
# ALB log delivery only supports SSE-S3 (not SSE-KMS), so AES256 is used here.

resource "aws_s3_bucket" "access_logs" {
  #checkov:skip=CKV_AWS_18:Exception SEC-04: this IS a log bucket; logging it would recurse
  #checkov:skip=CKV_AWS_144:Exception SEC-02: access logs are not replicated (cost)
  #checkov:skip=CKV2_AWS_62:Exception SEC-03: no consumer for log-object notifications
  #checkov:skip=CKV_AWS_145:Exception SEC-05: ALB log delivery only supports SSE-S3, not SSE-KMS
  count = var.enable_access_logs ? 1 : 0

  bucket        = "${var.name}-alb-logs-${data.aws_caller_identity.current.account_id}"
  force_destroy = var.access_logs_force_destroy

  tags = var.tags
}

resource "aws_s3_bucket_public_access_block" "access_logs" {
  count = var.enable_access_logs ? 1 : 0

  bucket                  = aws_s3_bucket.access_logs[0].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "access_logs" {
  count = var.enable_access_logs ? 1 : 0

  bucket = aws_s3_bucket.access_logs[0].id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

# trivy:ignore:AWS-0132 Exception SEC-05: ALB log delivery supports SSE-S3 only
resource "aws_s3_bucket_server_side_encryption_configuration" "access_logs" {
  count = var.enable_access_logs ? 1 : 0

  bucket = aws_s3_bucket.access_logs[0].id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_versioning" "access_logs" {
  count = var.enable_access_logs ? 1 : 0

  bucket = aws_s3_bucket.access_logs[0].id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "access_logs" {
  count = var.enable_access_logs ? 1 : 0

  bucket = aws_s3_bucket.access_logs[0].id

  rule {
    id     = "expire-logs"
    status = "Enabled"
    filter {}

    expiration {
      days = var.access_logs_retention_days
    }
    noncurrent_version_expiration {
      noncurrent_days = 7
    }
    abort_incomplete_multipart_upload {
      days_after_initiation = 1
    }
  }
}

data "aws_iam_policy_document" "access_logs" {
  count = var.enable_access_logs ? 1 : 0

  # Regions launched before Aug 2022 deliver as the regional ELB account...
  statement {
    sid       = "ElbAccountWrite"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.access_logs[0].arn}/${var.name}/AWSLogs/${data.aws_caller_identity.current.account_id}/*"]
    principals {
      type        = "AWS"
      identifiers = [data.aws_elb_service_account.current.arn]
    }
  }

  # ...newer regions use the log-delivery service principal.
  statement {
    sid       = "LogDeliveryWrite"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.access_logs[0].arn}/${var.name}/AWSLogs/${data.aws_caller_identity.current.account_id}/*"]
    principals {
      type        = "Service"
      identifiers = ["logdelivery.elasticloadbalancing.amazonaws.com"]
    }
  }

  statement {
    sid     = "DenyInsecureTransport"
    effect  = "Deny"
    actions = ["s3:*"]
    resources = [
      aws_s3_bucket.access_logs[0].arn,
      "${aws_s3_bucket.access_logs[0].arn}/*",
    ]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "access_logs" {
  count = var.enable_access_logs ? 1 : 0

  bucket = aws_s3_bucket.access_logs[0].id
  policy = data.aws_iam_policy_document.access_logs[0].json

  depends_on = [aws_s3_bucket_public_access_block.access_logs]
}
