# Week 1: AWS Foundations & Automation (Console → CLI → Terraform)

## Overview
Completed a 3-phase AWS cloud infrastructure lab manually via Console/CLI,
then replicated the entire setup using Terraform.

## Phase 1: Foundations Setup
- **EC2**: Launched free-tier t2.micro Amazon Linux 2 instance, SG allows SSH (22) + HTTP (80), key pair `my-aws-key.pem`
- **S3**: Created `harish-aws-lab-bucket` with versioning enabled, all public access blocked
- **IAM**: Created `ec2-s3-access-role` with least-privilege policy (PutObject, GetObject, ListBucket), attached to EC2 — no hardcoded credentials

## Phase 2: Application Setup
- Installed Apache (httpd) + cronie on EC2
- Deployed sample HTML page to `/var/www/html/index.html`
- Uploaded generated logs to `s3://harish-aws-lab-bucket/logs/app.log`
- Demonstrates stateless compute — EC2 holds no persistent state

## Phase 3: Automation
- Created `cloud_automate.sh` to generate timestamped logs and upload to S3 via CLI
- Scheduled via cron to run every minute
- Verified continuous S3 log updates with no manual intervention

## Terraform Replication
All 3 phases replicated as code. Resources provisioned:
- EC2 instance (t2.micro, Amazon Linux 2)
- S3 bucket with versioning + public access block
- IAM role + policy attachment + instance profile
- Security group (SSH + HTTP)
- Key pair

Website verified at: http://13.218.40.43

See `/terraform` folder for all `.tf` files and `userdata.sh`.
