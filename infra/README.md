# infra/ — Terraform

The foundation of talk-booking: remote state (S3), VPC, EKS, ECR, RDS, and the in-cluster
platform installed by Terraform — ArgoCD with the root Application, External Secrets
Operator, the AWS Load Balancer Controller, the monitoring stack.

## Layers: persistent vs ephemeral

| layer | resources | lifetime |
| --- | --- | --- |
| **persistent** | S3 state bucket, ECR | always on (cheap); protected by `prevent_destroy` |
| **ephemeral** | VPC, NAT, EKS, RDS and everything installed into the cluster | created at the start of a session, destroyed at the end (expensive) |

## Session ritual

```bash
make up          # create the stand (~20 min) and update kubeconfig
make values      # copy the new secret ARN and database host into the gitops values;
                 # the script prints the commit command — run it, or ArgoCD keeps the old ones
# ... work ...
make down        # tear down the ephemeral layer; the bucket and ECR stay
make leftovers   # anything billable still in AWS; empty means clean
```

`make down` asks for confirmation once, before doing anything, then:
1. removes automated sync from every Application, so ArgoCD cannot recreate an Ingress;
2. deletes `ExternalSecret` objects while the ESO controller is still alive to release
   their finalizers;
3. deletes Ingresses and waits for the load balancer to disappear. Terraform does not own
   the ALB — the controller does, and it must clean up before it is destroyed;
4. destroys the ephemeral layer by a target list (retried up to three times);
5. runs `make leftovers`.

The teardown goes by an explicit target list, not a bare `terraform destroy`: the latter
would stop at `prevent_destroy` on the state bucket and ECR. The list lives in the
`Makefile` as `EPHEMERAL`. When adding a resource to the ephemeral layer, add it there, or
it will survive `make down` and keep costing money.

Other targets: `make status` (what is alive in the cloud), `make cost` (how long the stand
has lived and what it cost), `make snapshots` (final RDS snapshots from past sessions —
each teardown leaves one, and they accumulate), `make orphans` (delete ALBs and target
groups left behind when the controller is already gone).

## Cost

About **$0.23 per hour** with three `t3.small` nodes, the NAT gateway and a
`db.t3.micro` RDS instance; the EKS control plane is the largest item. An ALB adds about
$0.02 per hour. The persistent layer (S3 state, ECR images, the latest final snapshot)
costs cents per month.

## Decisions

The reasoning lives in the ADRs (in Russian for now):
[CI → AWS auth](../docs/adr/14-ci-auth-masked-vars.md) ·
[EKS Secrets encryption](../docs/adr/17-eks-secrets-encryption-off.md) ·
[RDS protection flags](../docs/adr/19-rds-safety-flags.md).
