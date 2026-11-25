#!/usr/bin/env bash
# Outbound path from a pod: Cloud WAN -> egress group -> firewall -> NAT -> internet.
#
#   allowed  HTTPS (443) to the internet                expect success
#   allowed  source IP seen by the internet             expect one of the egress VPC NAT EIPs
#   blocked  HTTP (80) to the internet                  expect timeout (egress allowlist)
#   blocked  other TCP ports                            expect timeout

source "$(dirname "$0")/lib.sh"

NAT_IPS=$(tf_out_json network nat_public_ips | jq -r '.[]')

ensure_test_pod

info "Egress: allowed"
code=$(status in_pod curl --max-time 15 https://aws.amazon.com/)
case "$code" in
  2*|3*) pass "HTTPS to aws.amazon.com -> $code" ;;
  *)     fail "HTTPS to aws.amazon.com -> $code" ;;
esac

egress_ip=$(in_pod curl -sS --max-time 15 https://checkip.amazonaws.com 2>/dev/null | tr -d '[:space:]' || true)
if echo "$NAT_IPS" | grep -qx "$egress_ip"; then
  pass "internet sees the pod as $egress_ip (egress VPC NAT gateway)"
else
  fail "egress IP '$egress_ip' is not an egress VPC NAT EIP ($(echo $NAT_IPS))"
fi

info "Egress: blocked"
code=$(status in_pod curl --connect-timeout 5 --max-time 8 http://example.com/)
[ "$code" = "000" ] && pass "HTTP (80) to example.com blocked" || fail "HTTP (80) to example.com -> $code, expected blocked"

code=$(status in_pod curl --connect-timeout 5 --max-time 8 https://portquiz.net:8443/)
[ "$code" = "000" ] && pass "TCP 8443 to the internet blocked" || fail "TCP 8443 to the internet -> $code, expected blocked"

[ "${KEEP_TEST_POD:-}" = "1" ] || cleanup_test_pod
summary
