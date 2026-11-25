#!/usr/bin/env bash
# Runs every AWSM-28 dev test and exits non-zero if any failed.
set -uo pipefail

dir="$(dirname "$0")"
status=0

for t in test-ingress.sh test-egress.sh test-lattice.sh test-inspection.sh; do
  printf '\n=================== %s\n' "$t"
  KEEP_TEST_POD=1 bash "$dir/$t" || status=1
done

kubectl -n sample-app delete pod awsm28-netcheck awsm28-lattice-caller --ignore-not-found --wait=false >/dev/null 2>&1 || true
exit $status
