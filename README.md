# Client AWS landing zone: network, internet paths, VPC Lattice (dev)

Terraform and Helm for the network account (core network, inspection, Inbound VPC, IPAM, Lattice
service network) and a workload account (internet ingress, EKS, services published through VPC
Lattice), built to these ADRs:

| ADR | Topic | Where |
|---|---|---|
| ADR-32 | IP address management (IPAM pools, blocks, account ranges) | `modules/ipam`, `prod/network-ipam`, VPC CIDRs |
| ADR-34 | Core network: Cloud WAN segments, inspection, hybrid | `dev/network` |
| ADR-36 | Service connectivity: VPC Lattice | `modules/vpc-lattice-*`, `dev/network`, `dev/workloads-network`, `dev/workloads-lattice` |
| ADR-38 | TFE access: OIDC dynamic credentials, plan/apply roles | `modules/iam-tfe-oidc`, `dev/tfe-access` |
| ADR-42 | Terraform platform: modules, folders, workspaces, state | repo layout, `versions.tf`, `.github/workflows` |
| ADR-44 | Resource naming | `modules/context` (+ `resource-types.json`) |
| ADR-46 | Resource tagging (incl. MAP tags) | `modules/context`, provider `default_tags`, launch templates, LBC |

## Traffic paths

```
Customer inbound (HTML hops 0-3)
  Customer -> Route 53 app.<domain> -> CloudFront (WAF #1) -> origin.<domain> -> IGW
    -> edge route table -> GWLB endpoint -> GWLB -> firewall -> GWLB endpoint
    -> public ALB (SG: CloudFront prefix list only; WAF #2: secret header only)
    -> frontend pods (HTTPS 8443)

Service to service (HTML hops 4-6b, ADR-36)
  frontend pod (Pod Identity role "dev-workloads-frontend", SigV4)
    -> https://backend.dev.client.internal (private zone CNAME -> Lattice DNS, 169.254.171.x)
    -> VPC Lattice: network policy (organization only) AND service policy (frontend role, GET/HEAD)
    -> internal ALB (SG: Lattice prefix list only) -> backend pods (HTTPS 8443)
  Databases in other VPCs: resource gateway + resource configuration (hops 7a-7b, optional)

Outbound to internet (ADR-34)
  pod -> 0.0.0.0/0 -> Cloud WAN segment devworkloads -> send-to group devegress
    -> egress VPC: attachment -> GWLB endpoint -> GWLB -> firewall -> GWLB endpoint -> NAT -> IGW
  Replies: NAT -> GWLB endpoint (same AZ) -> firewall -> Cloud WAN. Appliance mode keeps both
  directions in one AZ, so on one stateful firewall.

On-premises (ADR-34/36; segments and VPC built, SD-WAN/DX attachments when the circuits exist)
  SD-WAN / Direct Connect segment -> (shared) devinbound segment -> Inbound VPC attachment
    -> GWLB endpoint -> firewall -> Route 53 Resolver inbound endpoint (DNS)
                                 -> Lattice service network endpoint (signed calls, Roles Anywhere)
  On-premises never has a route to a workload segment.
```

## Layout (ADR-42)

```
modules/                      one module per AWS service, no provider blocks
  context                     ADR-44 names + ADR-46 tags; resource-types.json = the ADR-43 table
  vpc                         VPC (IPAM pool or pinned CIDR), tiers per AZ, NAT, flow logs
  ipam                        IPAM, scopes, global -> regional -> OU pools, sandbox, RAM shares
  cloudwan-core-network       global/core network, segments, groups, send-to, segment sharing
  cloudwan-vpc-attachment     VPC attachment (tag-based placement, appliance mode)
  gateway-load-balancer       GWLB, GENEVE target group, endpoint service
  firewall-asg                firewall per AZ (gwlbtun stand-in until the VM-Series image)
  vpc-endpoint                Interface / Gateway / GWLB / Lattice ServiceNetwork / Resource
  vpc-lattice-service-network service network, AWS_IAM org policy, access logs, RAM share
  vpc-lattice-service         service, custom domain, HTTPS listener/rules, target groups,
                              deny-by-default auth policy, access logs, network association
  vpc-lattice-resource-gateway resource gateway + resource configurations (databases)
  vpc-lattice-vpc-association VPC <-> service network association with security groups
  route53-resolver-endpoint   Resolver inbound/outbound endpoint + DNS security group
  iam-roles-anywhere          trust anchor, profile and roles for on-premises callers
  iam-tfe-oidc                TFE OIDC provider + per-workspace plan (read-only) / apply roles
  security-group, network-acl, alb, acm-certificate, route53-zone, route53-record,
  wafv2-web-acl, cloudfront-distribution, shield-advanced, eks-cluster, iam-role, kms-key
dev/<stack>/                  one folder = one TFE workspace "dev-<stack>", applied in this order
  tfe-access                  bootstrap (admin credentials, not TFE): OIDC provider + roles
  network                     network account: Cloud WAN, egress VPC + firewalls, Inbound VPC,
                              Resolver, Lattice service network + endpoint
  workloads-network           workload VPC, GWLB endpoints, attachment, Lattice association, SGs
  workloads-edge              public zone, certificates, public ALB, WAFs, CloudFront
  workloads-eks               EKS, KMS, LBC role, Lattice caller roles (Pod Identity)
  workloads-lattice           internal ALBs, Lattice services, private zone, resource gateway
  workloads-platform          Helm: LBC, cert-manager, frontend + backend sample releases
prod/network-ipam             the organization IPAM in network-prod (ADR-32 pool table)
charts/                       cert-manager-issuers, sample-app (frontend and backend releases)
tests/                        ingress, egress, lattice, inspection
```

Modules are local paths here. In the target layout each module is its own repository
`terraform-aws-<name>` published to the TFE registry by Git tag (`0.0.x` test, `1.0.0+` prod),
and stacks call `source = "tfe.client.com/client/<name>/aws"` with an exact `version`.

## Names and tags

`modules/context` builds every top-level name: `{environment}-{function}[-{descriptor}][-dr][-suffix]`
in the form the resource type accepts (hyphens, snake case, lowercase alphanumerics, camel case),
read from `resource-types.json`. The plan fails if a type has no row, a required descriptor is
missing, or a name is too long (names are never cut). Examples in dev:

| Resource | Name |
|---|---|
| Workload VPC / subnets | `dev-workloads`, `dev-workloads-private-az1` |
| Egress / Inbound VPC | `dev-network-egress`, `dev-network-inbound` |
| NAT gateway | `dev-network-egress-nat-az1` |
| Cloud WAN segments / group | `devworkloads`, `devsdwan`, `devdirectconnect`, `devinbound` / `devegress` |
| Service network / service | `dev-network-services`, `dev-workloads-backend` |
| Public / internal ALB | `dev-workloads-public`, `dev-workloads-backend` |
| Paths | `/dev/workloads/cloudfront-origin-verify`, `/dev/network/egress-flow-logs` |

Tags (ADR-46): `environment, owner, jira_ticket, terraform, compliance, backup_required,
dr_required` (+ `application`, `tier`) and both MAP tags (`map-migrated`,
`aws-apn-id-656441707956`) go into every provider's `default_tags`. Node and firewall root
volumes, instances and ENIs get them through the launch templates; the Load Balancer Controller
gets them as `defaultTags`. Values are validated (owner, compliance, tier, lowercase).

## Decisions and deviations

| # | ADR says | Built | Why |
|---|---|---|---|
| 1 | Non-prod accounts use 1 AZ (ADR-32 §5) | Dev uses 2 AZs inside the ADR-32 dev ranges | ALB, EKS, GWLB and Resolver endpoints need two AZs. Host counts still meet the ADR (e.g. egress 2x4 /28 = 88 usable >= 64). |
| 2 | Inbound VPC on the shared Inbound segment (ADR-34); no range in ADR-32 | `10.200.107.128/25`, the next free /25 of the Network OU pool | Needed for the on-premises path to the Resolver and the Lattice endpoint. |
| 3 | Segment names `clientProd`, ... (ADR-34) | `devworkloads`, `devinbound`, ... | ADR-44 consequence: env first, priority 3 lowercase. |
| 4 | Core network and service networks owned by network-prod | Owned by the stack's network account (`network-dev` here) | Dev runs in one test account; prod passes network-prod. |
| 5 | Firewall decrypts | Stand-in passes traffic through (single-arm) | Vendor VM-Series image and Strata Cloud Manager config are AWSM-27. |
| 6 | One NAT, "Multi-AZ" (diagram) | One NAT per AZ, no single-NAT option | NAT is zonal; a shared NAT would return traffic through another AZ's firewall. |

## Open items: how the code handles them

Nothing below changes an ADR; these are the defaults the code uses until the owners decide.

| ADR | Open item | Code |
|---|---|---|
| 36 | EKS target type | Internal ALB per service (Terraform-owned; LBC TargetGroupBinding). The service module also takes IP/INSTANCE/LAMBDA target groups. |
| 36 | Backend pods -> RDS Proxy | Calls inside one VPC stay in the VPC; resource configurations are for callers in other VPCs. |
| 36 | Default domain or custom domains | Custom domains in `<env>.client.internal` with an ACM certificate (`certificate_arn`, Client CA). Without one, a dev CA stand-in is generated and its bundle mounted into pods. |
| 36 | Service network layout | One per environment (dev/test/uat/prod), so prod and non-prod never share one. |
| 36 | On-premises callers | IAM Roles Anywhere module, enabled by `onprem_ca_certificate_pem`; their roles go into service policies like any caller. |
| 36 | Access logs | Service network and every service log; set the Log Archive destination ARNs, otherwise local log groups. |
| 34 | DX / SD-WAN | Segments, sharing and the Inbound VPC are built; DX gateway attachment when `direct_connect_gateway_arn` is set. Connect attachments for SD-WAN come with the appliances. |
| 34 | Egress policy denies workload-to-workload | Firewall policy (Strata Cloud Manager). The stand-in does not filter. |
| 38 | Plan and apply roles | Separate read-only plan role and stack-scoped apply role per workspace (no account-wide admin). |
| 38 | Who creates IdP/roles in a new account | `dev/tfe-access` (bootstrap, admin credentials); the module fits the AFT account baseline. |
| 42 | Workspace split | One workspace per stack folder, split by account and layer, so every workspace's role is in its own account (ADR-38). |
| 42/46 | Tag check in pull requests | The context module fails the plan on missing/invalid tags; `.github/workflows/terraform-checks.yml` runs fmt, validate, tflint and Trivy. |
| 44 | Resource type table | `modules/context/resource-types.json` mirrors the ADR-43 epic table; add a row before a module uses a new type. |
| 46 | MAP tag values | From the ADR (`mig7MZ9CR0FKE`, `pc:dr0w726iea60dam948rtax9zm`); variable `map_tags` if the partner contact corrects them. |

Outside these stacks (management account): the SCPs that deny VPCs without IPAM (ADR-32) and core
network policy changes by anyone but the network pipeline (ADR-34), IPAM delegated
administration, and RAM sharing with AWS Organizations.

## Deploy

Prerequisites: Terraform >= 1.11, AWS CLI v2, kubectl, Helm 3, jq.

```bash
for s in tfe-access network workloads-network workloads-edge workloads-eks workloads-lattice workloads-platform; do
  cp dev/$s/terraform.tfvars.example dev/$s/terraform.tfvars   # then edit
done

terraform -chdir=dev/tfe-access init && terraform -chdir=dev/tfe-access apply      # once, admin
terraform -chdir=dev/network init && terraform -chdir=dev/network apply
terraform -chdir=dev/workloads-network init && terraform -chdir=dev/workloads-network apply
terraform -chdir=dev/workloads-edge init && terraform -chdir=dev/workloads-edge apply -target=module.zone
#   -> delegate domain_name to the name_servers output, then:
terraform -chdir=dev/workloads-edge apply
terraform -chdir=dev/workloads-eks init && terraform -chdir=dev/workloads-eks apply
terraform -chdir=dev/workloads-lattice init && terraform -chdir=dev/workloads-lattice apply
terraform -chdir=dev/workloads-platform init && terraform -chdir=dev/workloads-platform apply
```

Destroy in reverse order. `prod/network-ipam` is applied once in network-prod.

## State and Terraform Enterprise

The stacks are written for TFE runs:

- **Cross-stack reads**: `remote-state.tf` reads the other stacks' outputs with `tfe_outputs`
  (organization `tfe_organization`, workspace `<environment>-<stack>`). Every producing workspace
  must share its state with its readers (workspace setting "Remote state sharing", set in
  `terraform_enterprise`). Local runs need `TFE_TOKEN` or `terraform login tfe.client.com`, and
  the producing stacks' state must already be in TFE.
- **AWS credentials**: no `profile` in `terraform.tfvars`. Each workspace sets the env vars from
  `dev/tfe-access`'s `tfe_workspace_variables` output (`TFC_AWS_PROVIDER_AUTH=true`, plan/apply
  role ARNs). For a local run, export `AWS_PROFILE`. `dev/tfe-access` is the exception: a
  bootstrap stack run locally with admin credentials.
- **Helm**: the EKS token comes from `aws_eks_cluster_auth` (the AWS provider's credentials), so
  runners need no AWS CLI.
- **EKS API endpoint**: `public_access_cidrs` in `dev/workloads-eks/terraform.tfvars` lists the
  TFE runners' egress CIDRs. `detect_my_ip` is automatic: local runs add this machine's public IP (/32, re-detected each
  plan, output `detected_ip`); TFE runs (recognized by their plan/apply role) skip it. With an empty
  list the endpoint is private, and runners need a network path into the VPC.

To move a stack to TFE: uncomment the `cloud {}` block in its `versions.tf` (workspace
`dev-<stack>`) and run `terraform init` to migrate its state, in apply order (network first).
`workloads-edge` (origin secret) and `workloads-lattice` (dev CA keys) hold secrets in state:
delete the local `terraform.tfstate*` files after migrating.

## Test

```bash
$(terraform -chdir=dev/workloads-eks output -raw kubeconfig_command)
AWS_PROFILE=<apps-profile> tests/run-all.sh
```

| Test | Checks |
|---|---|
| test-ingress.sh | `https://app.<domain>` 200 through CloudFront; HTTP -> 301; SQLi -> 403; direct ALB access dropped; ALB web ACL defaults to Block |
| test-egress.sh | pod HTTPS out works and leaves from an egress VPC NAT EIP; HTTP/80 and 8443 blocked |
| test-lattice.sh | backend domain resolves to 169.254.171.x; signed GET as frontend -> 200 from backend pods; unsigned -> 403; signed DELETE -> 403; pod without the role -> 403 |
| test-inspection.sh | tcpdump on every firewall sees GENEVE for inbound and outbound traffic |

## Firewall stand-in and the real firewall (AWSM-27)

`modules/firewall-asg` runs the AWS GWLB tunnel handler (built from `gwlbtun_version` at boot; ASG
grace period 15 minutes) in single-arm mode: every flow returns to the GWLB. To use VM-Series, set
`ami_id`, `user_data_override` and `instance_type` in `dev/network`'s `module "firewall"`; GWLB,
endpoints and routes stay. Firewall policy (geo-blocking, workload-to-workload deny) lives in
Strata Cloud Manager, deployed by separate Terraform (ADR-34).

## Cost notes (dev)

Cloud WAN edge and attachments (3), NAT gateways (one per AZ), GWLB + endpoints (6), public and
internal ALBs, CloudFront, two web ACLs, the exportable certificate, Resolver endpoint (2 ENIs),
Lattice service network (VPC association, service, endpoint, requests), EKS control plane and
nodes. Shield Advanced stays off.
