#!/usr/bin/env bash
# Proves both paths cross the firewall: starts tcpdump (GENEVE, UDP 6081) on every firewall
# instance through Session Manager, generates inbound (CloudFront) and outbound (pod) traffic,
# then checks each instance captured packets.
#
# The firewall instances are in the network account: set NETWORK_AWS_PROFILE if it differs from
# AWS_PROFILE.

source "$(dirname "$0")/lib.sh"

NET_PROFILE_ARGS=()
[ -n "${NETWORK_AWS_PROFILE:-}" ] && NET_PROFILE_ARGS=(--profile "$NETWORK_AWS_PROFILE")
NET_REGION=$(tf_out network region)
CAPTURE_SECONDS=40

net_aws() { aws ${NET_PROFILE_ARGS[@]+"${NET_PROFILE_ARGS[@]}"} --region "$NET_REGION" "$@"; }

info "Inspection: finding firewall instances"
instance_ids=()
for asg in $(tf_out_json network firewall_asg_names | jq -r '.[]'); do
  ids=$(net_aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names "$asg" \
    --query 'AutoScalingGroups[0].Instances[?LifecycleState==`InService`].InstanceId' --output text)
  for id in $ids; do instance_ids+=("$id"); echo "  $asg: $id"; done
done
[ "${#instance_ids[@]}" -gt 0 ] || { fail "no InService firewall instances"; summary; exit 1; }

command_id=$(net_aws ssm send-command \
  --document-name AWS-RunShellScript \
  --instance-ids "${instance_ids[@]}" \
  --comment "AWSM-28 inspection test" \
  --parameters "{\"commands\":[\"timeout $CAPTURE_SECONDS tcpdump -nn -i any -c 50 udp port 6081 2>&1 | grep 'packets captured' || echo '0 packets captured'\"]}" \
  --query 'Command.CommandId' --output text)

info "Inspection: generating traffic for ~$((CAPTURE_SECONDS - 10))s"
sleep 5
ensure_test_pod
end=$((SECONDS + CAPTURE_SECONDS - 10))
while [ $SECONDS -lt $end ]; do
  curl -s -o /dev/null --max-time 5 "$APP_URL" || true                      # inbound
  in_pod curl -s -o /dev/null --max-time 5 https://aws.amazon.com/ || true  # outbound
done

sleep 12
info "Inspection: results"
for id in "${instance_ids[@]}"; do
  out=$(net_aws ssm get-command-invocation --command-id "$command_id" --instance-id "$id" \
    --query 'StandardOutputContent' --output text 2>/dev/null || echo "")
  n=$(echo "$out" | awk '/packets captured/{print $1}')
  if [ "${n:-0}" -gt 0 ]; then
    pass "$id captured $n GENEVE packets"
  else
    fail "$id captured no GENEVE packets (output: ${out:-none})"
  fi
done

[ "${KEEP_TEST_POD:-}" = "1" ] || cleanup_test_pod
summary
