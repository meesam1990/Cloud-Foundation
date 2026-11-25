#!/usr/bin/env bash
# Customer inbound path: CloudFront -> (IGW -> GWLB endpoint -> firewall) -> public ALB -> pods.
# Certificates are public, so curl verifies them normally.
#
#   allowed  https://app.<domain>/ from this machine            200, pod saw TLS, via CloudFront
#   allowed  http://app.<domain>/                               301 to HTTPS (CloudFront)
#   blocked  SQL injection probe through CloudFront             403 (CloudFront web ACL)
#   blocked  this machine -> public ALB directly                no connection (ALB security group)
#   blocked  pod -> public ALB (leaves through the firewall)    no connection (ALB security group)
#   config   ALB web ACL: default block, allow on origin header (only CloudFront can reach the ALB,
#            so the header rule cannot be exercised from outside)

source "$(dirname "$0")/lib.sh"

info "Ingress through CloudFront: $APP_URL"
code=$(status curl --max-time 20 "$APP_URL")
[ "$code" = "200" ] && pass "$APP_URL -> 200 (certificate verified)" || fail "$APP_URL -> $code, expected 200"

body=$(curl -sS --max-time 20 "$APP_URL" || true)
echo "$body" | grep -q '"tls":"TLSv1' && pass "pod received the request over TLS ($(echo "$body" | jq -r .tls 2>/dev/null))" \
  || fail "pod response does not show TLS: $body"
echo "$body" | jq -e '.via | test("CloudFront")' >/dev/null 2>&1 && pass "request came through CloudFront" \
  || fail "no CloudFront Via header in the pod's view: $body"

code=$(status curl --max-time 20 "http://$APP_FQDN/")
[ "$code" = "301" ] && pass "plain HTTP redirected to HTTPS (301)" || fail "plain HTTP -> $code, expected 301"

code=$(status curl --max-time 20 "$APP_URL?id=1%27%20OR%20%271%27=%271")
[ "$code" = "403" ] && pass "SQL injection probe blocked at CloudFront (403)" || fail "SQL injection probe -> $code, expected 403"

info "Ingress bypassing CloudFront"
code=$(status curl --connect-timeout 5 --max-time 10 --connect-to "$ORIGIN_FQDN:443:$ALB_DNS:443" "https://$ORIGIN_FQDN/")
[ "$code" = "000" ] && pass "public ALB drops a direct connection from this machine" || fail "direct ALB connection -> $code, expected none"

ensure_test_pod
code=$(status in_pod curl --connect-timeout 5 --max-time 10 --connect-to "$ORIGIN_FQDN:443:$ALB_DNS:443" "https://$ORIGIN_FQDN/")
[ "$code" = "000" ] && pass "public ALB drops a connection from a pod (egress NAT address)" || fail "pod -> ALB -> $code, expected none"

info "ALB web ACL configuration"
waf_name=$(echo "$WAF_ALB_ARN" | awk -F/ '{print $(NF-1)}')
waf_id=$(echo "$WAF_ALB_ARN" | awk -F/ '{print $NF}')
acl=$(aws wafv2 get-web-acl --region "$REGION" --scope REGIONAL --name "$waf_name" --id "$waf_id" --query WebACL --output json)
echo "$acl" | jq -e '.DefaultAction | has("Block")' >/dev/null && pass "default action is Block" || fail "default action is not Block"
echo "$acl" | jq -e --arg h "$(echo "$ORIGIN_HEADER" | tr '[:upper:]' '[:lower:]')" \
  '[.Rules[] | select(.Action | has("Allow")) | .. | objects | select(has("SingleHeader")) | .SingleHeader.Name | ascii_downcase] | index($h) != null' >/dev/null \
  && pass "an Allow rule matches the $ORIGIN_HEADER header" || fail "no Allow rule on $ORIGIN_HEADER"

[ "${KEEP_TEST_POD:-}" = "1" ] || cleanup_test_pod
summary
