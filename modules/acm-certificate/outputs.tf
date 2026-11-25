output "arn" {
  description = "Certificate ARN; with wait_for_validation it is only known once the certificate is issued."
  value       = var.wait_for_validation ? aws_acm_certificate_validation.this[0].certificate_arn : aws_acm_certificate.this.arn
}

output "domain_name" {
  value = aws_acm_certificate.this.domain_name
}
