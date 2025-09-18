# Secure EC2 Docker on AWS with Terraform

![Terraform](https://img.shields.io/badge/Terraform-1.13%2B-623CE4?logo=terraform&logoColor=white)
![AWS](https://img.shields.io/badge/AWS-EC2%20%7C%20VPC%20%7C%20SSM-FF9900?logo=amazonaws&logoColor=white)
![Docker](https://img.shields.io/badge/Docker-Engine%20%26%20Compose-2496ED?logo=docker&logoColor=white)
![Security](https://img.shields.io/badge/Security-IMDSv2%20%7C%20KMS%20%7C%20SSM-green)
![OS](https://img.shields.io/badge/OS-Amazon%20Linux%202-232F3E)

A production‑grade example that provisions a secure Docker host on EC2 using Terraform. The instance runs in a private subnet, reachable only via AWS Systems Manager (SSM), with IMDSv2 enforced, EBS encryption (KMS CMK), hardened Docker defaults, CloudWatch metrics/logs, and opinionated SSM Patch/Maintenance.

This repository showcases practical DevOps, Cloud, and Security from end‑to‑end: clean IaC, secure-by-default architecture, auditable verification commands (great for screenshots), and a safe teardown path to control costs.

---

## Highlights (Secure by Default)
- Network
  - VPC with public subnet (NAT) and private subnet (EC2).
  - NAT Gateway for outbound updates/image pulls. No public IP on the instance.
  - VPC Interface Endpoints for SSM, SSMMessages, and EC2Messages in the private subnet.
- Compute & OS Hardening
  - Launch Template enforces IMDSv2 (http_tokens = required) and detailed monitoring (toggleable).
  - Root EBS gp3 with KMS CMK encryption; delete on termination.
  - SSM Patch Baseline (Security severity) with weekly Maintenance Window.
- Observability
  - CloudWatch Agent collects CPU/memory/disk metrics and system logs.
- Container Security
  - Hardened Docker defaults (live-restore, json-file logs, overlay2).
  - docker-compose services use: security_opt no-new-privileges, read-only FS, tmpfs (noexec,nosuid), non-root user.

---

## Architecture
![Secure EC2 Docker Architecture Diagram](/secure-ec2-Docker-Architecture-Diagram.png)

---

## Prerequisites
- Terraform >= 1.0 (tested with 1.13.2)
- AWS CLI v2
- An AWS account/role with permissions to create VPC, EC2, IAM, SSM, CloudWatch, KMS, and EIP/NAT resources
- Configured credentials (e.g., `aws configure` or env vars)
- Optional for local validation: Docker and Python 3

Operator IAM permissions (least-privilege):
- For production, prefer a constrained role; for learning, temporary AdministratorAccess is fine. Minimal actions (scope by ARNs/tags where possible):
  - ec2: Create/Delete/Describe for VPC/Subnet/IGW/RouteTable/NAT/EIP/SG/LaunchTemplate/Instance/VpcEndpoint/Tagging
  - iam: CreateRole, CreateInstanceProfile, AttachRolePolicy, PutRolePolicy, PassRole (scoped), Delete*, Get*, List*
  - logs: CreateLogGroup, CreateLogStream, PutLogEvents, DescribeLogGroups (scoped to /aws/ec2/*)
  - ssm: PatchBaseline, PatchGroup, MaintenanceWindow, SendCommand, StartSession, GetCommandInvocation
  - kms: CreateKey, CreateAlias, ScheduleKeyDeletion, DescribeKey, TagResource

Quick profile sanity check:
- aws sts get-caller-identity
- Ensure it shows the intended admin/role.

---

## Quick Start
1) Clone and set directory
- git clone https://github.com/ridwansukri/secure-ec2-docker.git
- cd secure-ec2-docker/terraform

2) Configure variables
- Copy `terraform.tfvars.example` to `terraform.tfvars` and adjust values if needed.

3) Authenticate to AWS
- export AWS_PROFILE=my-admin-profile  # or set env vars
- aws sts get-caller-identity          # verify

4) Initialize and plan
- terraform init -upgrade
- terraform validate
- terraform plan

5) Apply
- terraform apply -auto-approve

6) Outputs
- terraform output
- Notable outputs:
  - instance_id
  - aws_region
  - ssm_connection_command
  - vpc_id, private_subnet_id, security_group_id, nat_gateway_ip

---

## Security Verification (Great for screenshots)
1) IMDSv2 via EC2 API
- Make sure still in terraform folder
- aws ec2 describe-instances --instance-ids $(terraform output -raw instance_id) \
  --query "Reservations[].Instances[].MetadataOptions" --output table --region $(terraform output -raw aws_region)

Expected: HttpTokens = required, HttpEndpoint = enabled.

2) SSM shell verification
- IID=$(terraform output -raw instance_id)
- aws ssm send-command \
  --instance-ids $IID \
  --document-name AWS-RunShellScript \
  --comment "Security Verification" \
  --parameters file://../scripts/ssm-verify-params.json \
  --region $(terraform output -raw aws_region)
- aws ssm get-command-invocation --command-id <COMMAND_ID> --instance-id $IID --output text

The script prints:
- OS version, IMDSv2 token test, Docker/Compose versions
- /etc/docker/daemon.json
- docker-compose.yml security options (no-new-privileges, read_only, tmpfs)
- CloudWatch Agent status

3) Optional: Run the sample compose app
- aws ssm start-session --target $(terraform output -raw instance_id)
- sudo su - ec2-user
- docker compose -f /opt/app/docker-compose.yml up -d
- docker ps --no-trunc; curl -I http://localhost:80

---

## Teardown
- From repo root or scripts/: `./scripts/destroy.sh`
- Ensures dependency-friendly order and avoids NAT Gateway costs
- If using a different profile/role than apply time, ensure same account/region/permissions

---

## What This Repo Demonstrates
- Clean IaC with Terraform (providers, data sources, variables, outputs)
- Private-only compute with SSM connectivity (no public SSH)
- IMDSv2 enforcement and patch governance via SSM Maintenance Windows
- Least-privilege instance role (SSM + CloudWatch Agent + minimal Logs)
- Optional custom Patch Group: by default this demo uses AWS-managed AL2 baseline. For a custom baseline, tag the instance with PatchGroup=<your-group> (no space in key) and adjust SSM resources.
- Disk encryption with a dedicated KMS CMK, consistent tagging
- Docker Engine hardening + secure Compose defaults
- Operational hygiene: clear outputs, verification commands, and safe destroy

---

## Troubleshooting
- UnauthorizedOperation on plan/apply: switch to the correct profile (export AWS_PROFILE=...), confirm via `aws sts get-caller-identity`
- SSM not Managed: ensure VPCEs exist and the instance profile is attached; give it a few minutes
- NAT costs: consider VPC endpoints for ECR/Docker Hub mirror or temporarily disable pulls
- terraform output -raw instance_id empty: run inside `terraform/` and ensure apply succeeded
- Windows quoting for send-command: use the JSON params files under `scripts/`

Local validation helper
- `scripts/test_commands.sh` validates URLs and config snippets; gracefully skips checks if Docker/Python are missing

Local validation script
- The helper script scripts/test_commands.sh can be run locally to validate URLs and configs. It will gracefully skip Docker/Python checks if those tools are not installed.

---

## Clean Repo Practices
- `terraform/terraform.tfvars` is meant for local values and is ignored by .gitignore in this repo template.
- Commit `terraform.tfvars.example` for sharing sane defaults without secrets.


---

## 📄 License
This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 👨‍💻 Author

**Muh Ridwan Sukri**
- Website: [www.ridwansukri.com](https://www.ridwansukri.com)
- GitHub: [@ridwansukri](https://github.com/ridwansukri)
- LinkedIn: [Muh Ridwan Sukri](https://linkedin.com/in/ridwansukri)
- Email: [contact@ridwansukri.com](mailto:contact@ridwansukri.com)

## 🙏 Acknowledgments
- AWS documentation that guided this project:
  - EC2 Instance Metadata Service v2 (IMDSv2): https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/configuring-instance-metadata-service.html
  - Systems Manager Session Manager: https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager.html
  - VPC Interface Endpoints (SSM/SSMMessages/EC2Messages): https://docs.aws.amazon.com/vpc/latest/privatelink/vpc-endpoints.html
  - CloudWatch Agent (metrics and logs): https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/Install-CloudWatch-Agent.html
  - CloudWatch Dashboards: https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/CloudWatch_Dashboards.html
- Icons/badges used in this README:
  - shields.io badges: https://shields.io/
  - Simple Icons (used by shields): https://simpleicons.org/

---

⭐ Star this repo if you find it helpful!