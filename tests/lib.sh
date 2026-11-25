#!/usr/bin/env bash
# Shared helpers for the AWSM-28 dev tests. Source this file; do not run it.
#
# Needs: terraform, aws, kubectl (kubeconfig for the cluster, see workloads-eks kubeconfig_command), curl,
# jq. Set AWS_PROFILE to the apps account profile. The stacks' local state must be present (or
# swap tf_out for TFE outputs).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_DIR="$REPO_ROOT/dev"

PASS=0
FAIL=0

tf_out() { # tf_out <stack> <output>
  terraform -chdir="$ENV_DIR/$1" output -raw "$2"
}

tf_out_json() {
  terraform -chdir="$ENV_DIR/$1" output -json "$2"
}

pass() { PASS=$((PASS + 1)); printf '  \033[32mPASS\033[0m %s\n' "$*"; }
fail() { FAIL=$((FAIL + 1)); printf '  \033[31mFAIL\033[0m %s\n' "$*"; }
info() { printf '\n\033[1m%s\033[0m\n' "$*"; }

summary() {
  printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
  [ "$FAIL" -eq 0 ]
}

# HTTP status of a curl call, or 000 when no connection was made.
status() {
  "$@" -s -o /dev/null -w '%{http_code}' 2>/dev/null || true
}

# One long-lived curl pod in the sample-app namespace, for tests that must start inside the cluster
# (pod subnets, so they follow the real egress path through Cloud WAN and the firewall).
TEST_NS="sample-app"
TEST_POD="awsm28-netcheck"

ensure_test_pod() {
  if ! kubectl -n "$TEST_NS" get pod "$TEST_POD" >/dev/null 2>&1; then
    kubectl -n "$TEST_NS" run "$TEST_POD" --image=curlimages/curl:8.11.1 --restart=Never \
      --command -- sleep 3600 >/dev/null
  fi
  kubectl -n "$TEST_NS" wait --for=condition=Ready "pod/$TEST_POD" --timeout=180s >/dev/null
}

in_pod() {
  kubectl -n "$TEST_NS" exec "$TEST_POD" -- "$@"
}

cleanup_test_pod() {
  kubectl -n "$TEST_NS" delete pod "$TEST_POD" --ignore-not-found --wait=false >/dev/null 2>&1 || true
}

# ---------------------------------------------------------------- endpoints

REGION=$(tf_out workloads-network region)
APP_URL=$(tf_out workloads-edge app_url)
APP_FQDN=$(tf_out workloads-edge app_fqdn)
ORIGIN_FQDN=$(tf_out workloads-edge origin_fqdn)
ALB_DNS=$(tf_out workloads-edge alb_dns_name)
ORIGIN_HEADER=$(tf_out workloads-edge origin_verify_header_name)
ORIGIN_SECRET_ARN=$(tf_out workloads-edge origin_secret_arn)
WAF_ALB_ARN=$(tf_out workloads-edge waf_alb_arn)

origin_secret() {
  aws secretsmanager get-secret-value --region "$REGION" --secret-id "$ORIGIN_SECRET_ARN" \
    --query SecretString --output text
}
