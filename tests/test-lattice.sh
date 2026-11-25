#!/usr/bin/env bash
# Service-to-service path through VPC Lattice (ADR-36), from a pod running as the "frontend"
# service account (its Pod Identity role is the only caller the backend's auth policy names):
#
#   DNS      backend custom domain resolves to the Lattice link-local range   169.254.171.x
#   allowed  signed GET (SigV4, frontend role)                                200 from the backend pods
#   denied   unsigned GET                                                     403 (AWS_IAM, deny by default)
#   denied   signed DELETE (method not in the policy)                         403
#   denied   unsigned GET from a pod without the role                         403

source "$(dirname "$0")/lib.sh"

BACKEND_URL=$(tf_out_json workloads-lattice service_urls | jq -r '.backend // empty')
CA_PEM=$(tf_out_json workloads-lattice ca_bundle_pem | jq -r '. // empty')
CALLER_SA=$(tf_out_json workloads-eks lattice_callers | jq -r '.frontend.service_account // empty')

[ -n "$BACKEND_URL" ] || { fail "workloads-lattice has no backend service"; summary; exit 1; }
BACKEND_HOST=${BACKEND_URL#https://}

CALLER_POD="awsm28-lattice-caller"

info "Lattice: starting a caller pod as service account $CALLER_SA"
if ! kubectl -n "$TEST_NS" get pod "$CALLER_POD" >/dev/null 2>&1; then
  kubectl -n "$TEST_NS" run "$CALLER_POD" --image=curlimages/curl:8.11.1 --restart=Never \
    --overrides="{\"spec\":{\"serviceAccountName\":\"$CALLER_SA\"}}" --command -- sleep 3600 >/dev/null
fi
kubectl -n "$TEST_NS" wait --for=condition=Ready "pod/$CALLER_POD" --timeout=180s >/dev/null

caller() { kubectl -n "$TEST_NS" exec -i "$CALLER_POD" -- "$@"; }

# CA of the custom-domain certificate (the dev stand-in, or the Client CA's chain).
if [ -n "$CA_PEM" ]; then
  printf '%s\n' "$CA_PEM" | caller sh -c 'cat > /tmp/ca.crt'
  CACERT="--cacert /tmp/ca.crt"
else
  CACERT=""
fi

# Signed request with the Pod Identity credentials of the pod (curl --aws-sigv4).
signed() { # signed <method>
  caller sh -c "
    creds=\$(curl -s -H \"Authorization: \$(cat \$AWS_CONTAINER_AUTHORIZATION_TOKEN_FILE)\" \$AWS_CONTAINER_CREDENTIALS_FULL_URI)
    ak=\$(echo \"\$creds\" | sed -n 's/.*\"AccessKeyId\" *: *\"\\([^\"]*\\)\".*/\\1/p')
    sk=\$(echo \"\$creds\" | sed -n 's/.*\"SecretAccessKey\" *: *\"\\([^\"]*\\)\".*/\\1/p')
    tk=\$(echo \"\$creds\" | sed -n 's/.*\"Token\" *: *\"\\([^\"]*\\)\".*/\\1/p')
    curl -s -o /tmp/body -w '%{http_code}' --max-time 15 $CACERT -X $1 \
      --aws-sigv4 'aws:amz:$REGION:vpc-lattice-svcs' --user \"\$ak:\$sk\" \
      -H \"x-amz-security-token: \$tk\" -H 'x-amz-content-sha256: UNSIGNED-PAYLOAD' \
      $BACKEND_URL/
  " 2>/dev/null || echo 000
}

info "Lattice: DNS"
addr=$(caller nslookup "$BACKEND_HOST" 2>/dev/null | awk '/^Address: /{print $2}' | tail -1)
case "$addr" in
  169.254.171.*) pass "$BACKEND_HOST -> $addr (Lattice)" ;;
  *)             fail "$BACKEND_HOST -> '$addr' (expected 169.254.171.x)" ;;
esac

info "Lattice: allowed"
code=$(signed GET)
body=$(caller cat /tmp/body 2>/dev/null || true)
if [ "$code" = "200" ] && echo "$body" | grep -q '"app":"backend"'; then
  pass "signed GET as $CALLER_SA -> 200 from the backend pods"
else
  fail "signed GET as $CALLER_SA -> $code ($body)"
fi

info "Lattice: denied"
code=$(status caller curl --max-time 15 $CACERT "$BACKEND_URL/")
[ "$code" = "403" ] && pass "unsigned GET -> 403" || fail "unsigned GET -> $code (expected 403)"

code=$(signed DELETE)
[ "$code" = "403" ] && pass "signed DELETE (method not allowed by the policy) -> 403" || fail "signed DELETE -> $code (expected 403)"

ensure_test_pod
code=$(status in_pod curl --max-time 15 -k "$BACKEND_URL/")
[ "$code" = "403" ] && pass "pod without the caller role -> 403" || fail "pod without the caller role -> $code (expected 403)"

[ "${KEEP_TEST_POD:-0}" = "1" ] || { cleanup_test_pod; kubectl -n "$TEST_NS" delete pod "$CALLER_POD" --ignore-not-found --wait=false >/dev/null 2>&1 || true; }

summary
