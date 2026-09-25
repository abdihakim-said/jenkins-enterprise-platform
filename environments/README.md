# Environments

Only `dev/` is implemented today. It is the environment I deployed and tested.

| Setting | dev |
|---|---|
| VPC CIDR | 10.1.0.0/16 |
| Controller | t3.small, single active instance |
| NAT | single NAT gateway |
| Log / backup retention | 7 days |

Staging and production would be added as further `*.tfvars` files with their own backend state key. Several root variables (NAT count, ASG sizing) still need to be wired through to the modules first; see "Known limitations" in the main README.

```bash
terraform plan -var-file=environments/dev/terraform.tfvars
```
