# Week 1 Notes — Terraform Learning

## Commands I used
```bash
terraform init      # downloads AWS provider, sets up backend
terraform plan       # preview changes before applying
terraform apply       # creates the resources
terraform destroy      # tears everything down (used to avoid AWS charges)
```

## Key concepts I learned

**State file (`terraform.tfstate`)**
- Terraform's "memory" of what it created
- Never commit this to GitHub — added to `.gitignore`
- If lost, Terraform loses track of real infrastructure

**Declarative vs Console/CLI**
- Console/CLI = I tell AWS *how* to do each step manually
- Terraform = I describe the *end state*, Terraform figures out how

**IAM role vs hardcoded credentials**
- Attached `ec2-s3-access-role` directly to EC2 via instance profile
- EC2 can call S3 APIs without any access keys stored on the instance
- More secure, and credentials rotate automatically

**`user_data` script**
- Runs once on first boot only
- Used it to install Apache + cronie + set up the automation script
- Good for bootstrapping, not for ongoing configuration

## Gotchas I ran into
- `crontab` needs a trailing `-` at the end to read from stdin — missed this at first, cron job silently failed
- S3 bucket names must be globally unique across ALL of AWS, not just my account
- Forgot `force_destroy = true` initially — `terraform destroy` failed because the bucket had objects in it



