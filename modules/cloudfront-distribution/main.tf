# CloudFront distribution in front of one custom origin, for a dynamic application:
#
#   viewer side  aliases with an ACM certificate (us-east-1), HTTPS only (HTTP redirects),
#                TLS 1.2+, web ACL (CLOUDFRONT scope)
#   origin side  HTTPS only to origin_domain_name (its certificate must be publicly trusted and
#                match that name), with a secret header so the origin can reject anything that
#                did not come through this distribution
#   caching      off (CachingDisabled); all viewer headers, cookies and query strings are
#                forwarded except Host, so the origin receives Host = origin_domain_name

data "aws_cloudfront_cache_policy" "caching_disabled" {
  name = "Managed-CachingDisabled"
}

data "aws_cloudfront_origin_request_policy" "all_viewer_except_host" {
  name = "Managed-AllViewerExceptHostHeader"
}

data "aws_cloudfront_response_headers_policy" "security_headers" {
  name = "Managed-SecurityHeadersPolicy"
}

resource "aws_cloudfront_distribution" "this" {
  enabled             = true
  comment             = var.comment
  aliases             = var.aliases
  price_class         = var.price_class
  http_version        = "http2and3"
  is_ipv6_enabled     = true
  web_acl_id          = var.web_acl_arn
  wait_for_deployment = true

  origin {
    origin_id   = "primary"
    domain_name = var.origin_domain_name

    custom_origin_config {
      http_port                = 80
      https_port               = 443
      origin_protocol_policy   = "https-only"
      origin_ssl_protocols     = ["TLSv1.2"]
      origin_read_timeout      = var.origin_read_timeout
      origin_keepalive_timeout = 5
    }

    dynamic "custom_header" {
      for_each = var.origin_verify_header_name == null ? [] : [1]

      content {
        name  = var.origin_verify_header_name
        value = var.origin_verify_header_value
      }
    }
  }

  default_cache_behavior {
    target_origin_id           = "primary"
    viewer_protocol_policy     = "redirect-to-https"
    allowed_methods            = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods             = ["GET", "HEAD"]
    compress                   = true
    cache_policy_id            = data.aws_cloudfront_cache_policy.caching_disabled.id
    origin_request_policy_id   = data.aws_cloudfront_origin_request_policy.all_viewer_except_host.id
    response_headers_policy_id = data.aws_cloudfront_response_headers_policy.security_headers.id
  }

  viewer_certificate {
    acm_certificate_arn      = var.acm_certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  restrictions {
    geo_restriction {
      restriction_type = length(var.geo_allow_list) > 0 ? "whitelist" : "none"
      locations        = var.geo_allow_list
    }
  }

  dynamic "logging_config" {
    for_each = var.access_log_bucket == null ? [] : [1]

    content {
      bucket          = var.access_log_bucket
      prefix          = var.access_log_prefix
      include_cookies = false
    }
  }

  tags = { Name = var.comment }
}
