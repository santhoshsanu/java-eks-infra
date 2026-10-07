# java-eks-infra

Infrastructure as Code for the Java EKS Project.
Manages all AWS infrastructure using Terraform.

## What This Repo Manages

```
terraform/
├── versions.tf      ← Provider versions (AWS, Helm, Kubernetes)
├── backend.tf       ← Remote state (S3 + DynamoDB lock)
├── variables.tf     ← All input variables
├── terraform.tfvars ← Variable values
├── vpc.tf           ← VPC, subnets, NAT Gateway
├── eks.tf           ← EKS cluster, node group, OIDC, addons
├── ecr.tf           ← ECR repositories (backend + frontend)
├── iam.tf           ← IAM roles (EKS, node group, ALB controller)
└── helm.tf          ← ALB Controller + Metrics Server via Helm

iam/
└── alb-controller-policy.json   ← ALB controller IAM policy

docs/
├── step1-iam-setup.md           ← IAM bootstrap guide
├── step2-terraform-guide.md     ← Terraform usage guide
└── aws-cli-config-template.md   ← AWS CLI reference
```

## Infrastructure Created

| Resource | Details |
|----------|---------|
| VPC | 10.0.0.0/16, 2 public + 2 private subnets |
| EKS Cluster | Kubernetes 1.31, ap-south-1 |
| Node Group | m7i-flex.large, 50GB disk |
| ECR | java-eks-backend + java-eks-frontend |
| ALB Controller | Auto-installs via Helm |
| Metrics Server | Auto-installs via Helm |

## Usage

```bash
# Initialize
terraform init

# Plan
terraform plan -out=tfplan

# Apply
terraform apply tfplan

# Destroy
terraform destroy
```

## CI/CD Pipeline

GitHub Actions pipeline at `.github/workflows/infra-pipeline.yml`

| Trigger | Action |
|---------|--------|
| Push to `terraform/` | Plan only |
| Merge to `main` | Plan + Apply |
| Manual `destroy` | Destroy with approval |

## Related Repo

Application code → [java-eks-project](https://github.com/santhoshsanu/java-eks-project)
