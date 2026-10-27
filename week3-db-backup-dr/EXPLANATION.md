# Terraform Code Walkthrough — Week 3 (Database, Backup & DR)

A line-by-line explanation of what each file does and *why*, for anyone learning this
codebase. Read alongside [README.md](./README.md), which covers structure/inputs/outputs;
this file explains the mechanics and reasoning.

---

## 1. `providers.tf` — Who talks to AWS, and where

```hcl
provider "aws" {
  region = var.aws_region
  default_tags { tags = { ... } }
}

provider "aws" {
  alias  = "dr"
  region = var.dr_region
  default_tags { tags = { ... Purpose = "disaster-recovery" } }
}
```

- Terraform needs an AWS "provider" to know which account/region to call. Here there are
  **two** providers: the default one (primary region, e.g. `us-east-1`) and a second one
  with `alias = "dr"` pointed at `var.dr_region` (e.g. `us-west-2`).
- Why two? DR resources (the cross-region read replica) must physically live in a
  different AWS region. Terraform can only create a resource in one region per provider,
  so a second, aliased provider is the standard way to manage multi-region infrastructure
  in a single `terraform apply`.
- `default_tags` automatically stamps every resource created through that provider with
  `Project`, `Environment`, `ManagedBy=terraform`, `Owner` (and `Purpose=disaster-recovery`
  only on the DR provider). This means you never have to repeat `tags = {...}` on every
  resource block — it's inherited, and it's how cost/audit tooling can later filter
  "everything this project owns" or "everything that exists purely for DR".

## 2. `versions.tf` — Locking down the toolchain

```hcl
terraform {
  required_version = ">= 1.7.0"
  required_providers {
    aws     = { source = "hashicorp/aws", version = "~> 5.40", configuration_aliases = [aws.dr] }
    random  = { source = "hashicorp/random", version = "~> 3.6" }
    archive = { source = "hashicorp/archive", version = "~> 2.4" }
  }
  # backend "s3" { ... }  <- commented out
}
```

- `required_version` / `version = "~> 5.40"` pin Terraform and provider versions so that
  `terraform init` always resolves to compatible releases — this prevents "works on my
  machine" drift when a teammate (or CI) runs the same code six months later.
- `configuration_aliases = [aws.dr]` is what *allows* a module to accept the `aws.dr`
  provider alias as an input (see `providers = { aws = aws.dr }` pattern below). Without
  declaring it here, Terraform would reject any module trying to use a non-default provider.
- `random` and `archive` are declared but not yet used anywhere in the current `.tf` files.
  Their presence signals **intent**: `random` is typically used to generate unique suffixes
  (e.g., S3 bucket names) and `archive` is used to zip Lambda source code
  (`data "archive_file"`) before uploading it as a Lambda deployment package. This tells you
  a Lambda-based backup-automation resource is planned but not yet written (see README's
  "Gaps & Next Steps").
- The commented `backend "s3"` block shows *how* remote state would be wired in (S3 for the
  state file itself, DynamoDB table for state locking so two people can't `apply`
  simultaneously and corrupt state) — it's inactive until uncommented and filled in.

## 3. `variables.tf` — The root module's public API

Every variable here is an input the *root* module accepts. A few patterns worth understanding:

```hcl
variable "environment" {
  default = "dev"
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod."
  }
}
```
- `validation` blocks run at `terraform plan` time, before anything is created. This turns a
  typo like `environment = "produciton"` into an immediate, readable error instead of a
  partially-applied, misconfigured environment.

```hcl
variable "private_subnet_ids" {
  type = list(string)
  validation {
    condition     = length(var.private_subnet_ids) >= 2
    error_message = "Provide at least two private subnets in different Availability Zones..."
  }
}
```
- Enforces a *structural* precondition (Multi-AZ RDS requires 2+ subnets in different AZs)
  that AWS itself would only reject deep into resource creation — failing fast in
  Terraform saves a slow, confusing apply failure.

```hcl
variable "db_backup_retention_period" {
  default = 7
  validation {
    condition     = var.db_backup_retention_period >= 1 && var.db_backup_retention_period <= 35
    error_message = "db_backup_retention_period must be between 1 and 35."
  }
}
```
- Mirrors an actual AWS API constraint (RDS only accepts 1–35 days retention), documented
  and enforced in the same place a developer would set the value.

- Notice there's **no `db_password` variable**. That's intentional — see the RDS module
  section below on `manage_master_user_password`.
- Variables are grouped with `# ---` comment banners (Networking, RDS, DynamoDB, Backup
  automation) purely for human navigation; Terraform doesn't care about ordering.

## 4. `modules/rds/main.tf` — The primary database

Walking through top to bottom:

### KMS key
```hcl
resource "aws_kms_key" "rds" {
  deletion_window_in_days = 30
  enable_key_rotation     = true
}
```
- A **customer-managed key (CMK)**, not the AWS-owned default RDS key. Why bother? A CMK
  gives you an audit trail (CloudTrail logs every use of *this specific* key), lets you
  control who can use/administer it via a key policy, and lets you revoke access
  independently of the RDS instance. `enable_key_rotation = true` rotates the underlying
  key material yearly automatically, without re-encrypting existing data or changing the
  key's ARN. `deletion_window_in_days = 30` is a safety buffer — if someone tries to delete
  this key, AWS waits 30 days before actually destroying it (during which it can still be
  cancelled), because deleting a KMS key that encrypts an active database's storage would
  make that data permanently unreadable.

### Networking
```hcl
resource "aws_db_subnet_group" "this" {
  subnet_ids = var.private_subnet_ids
}

resource "aws_security_group" "rds" {
  egress { ... 0.0.0.0/0 ... }
}

resource "aws_security_group_rule" "ingress_mysql" {
  for_each                  = toset(var.app_security_group_ids)
  from_port                 = 3306
  to_port                   = 3306
  source_security_group_id  = each.value
}
```
- The subnet group tells RDS *which subnets* it's allowed to place ENIs in (must be private,
  must span ≥2 AZs for Multi-AZ to work).
- The security group has an open egress rule (databases need to reach out for things like
  patching, replication, CloudWatch) but **no ingress rules are hardcoded**. Instead,
  `aws_security_group_rule.ingress_mysql` uses `for_each` over
  `var.app_security_group_ids` to create one ingress rule *per* approved application
  security group — so instead of opening port 3306 to a CIDR block (an IP range, which is
  broad and drifts as infra changes), access is scoped to "whatever EC2/Lambda has been
  tagged with security group X". This is the AWS-recommended least-privilege pattern for
  intra-VPC access.

### Parameter group
```hcl
resource "aws_db_parameter_group" "this" {
  family = "mysql8.0"
  parameter {
    name  = "require_secure_transport"
    value = "1"
  }
}
```
- RDS parameter groups are how you change engine-level configuration (`my.cnf`-equivalent
  settings) outside of the console. Setting `require_secure_transport = 1` makes MySQL
  reject any client connection that isn't using TLS — this is what makes "encryption in
  transit" actually enforced, rather than just possible.

### The database instance itself
```hcl
resource "aws_db_instance" "this" {
  storage_encrypted = true
  kms_key_id         = aws_kms_key.rds.arn

  manage_master_user_password = true

  multi_az                = var.multi_az
  backup_retention_period  = var.backup_retention_period
  backup_window            = "03:00-04:00"
  maintenance_window       = "sun:04:30-sun:05:30"

  enabled_cloudwatch_logs_exports = ["error", "general", "slowquery"]
  performance_insights_enabled    = true

  deletion_protection       = var.deletion_protection
  skip_final_snapshot       = false
  final_snapshot_identifier = "${local.identifier}-final-${formatdate("YYYYMMDDhhmmss", timestamp())}"

  lifecycle {
    ignore_changes = [final_snapshot_identifier]
  }
}
```
- `storage_encrypted` + `kms_key_id`: every byte on disk, and every automated
  snapshot/backup taken from this instance, is encrypted with the CMK above.
- `manage_master_user_password = true` is the key security decision in this module: instead
  of you supplying a password (which would then live in Terraform state — a file that must
  itself be protected), **AWS generates a random, strong password and stores it in Secrets
  Manager**, rotating it automatically. Terraform never sees or stores the plaintext value;
  applications retrieve it at runtime from Secrets Manager using the ARN in
  `output "master_user_secret_arn"`.
- `backup_retention_period` (from the validated root variable) + `backup_window` control
  **automated backups**: RDS takes a full daily snapshot in that window and continuously
  archives transaction logs, which together is what enables point-in-time recovery (you can
  restore to *any second* within the retention window, not just to a snapshot boundary).
- `enabled_cloudwatch_logs_exports` ships the MySQL error/general/slow-query logs to
  CloudWatch Logs, so you can search/alert on them without SSHing anywhere (there's nowhere
  to SSH to — it's a managed database).
- `performance_insights_enabled` turns on a built-in, low-overhead query performance
  dashboard (top SQL by load, wait events) — useful for diagnosing slow queries in
  production without installing extra tooling.
- `skip_final_snapshot = false` + `final_snapshot_identifier`: if this instance is ever
  destroyed (`terraform destroy` or replacement), AWS is forced to take one last named
  snapshot first, so "someone ran destroy" can never mean "the data is gone with zero
  recovery path". The identifier embeds a timestamp so re-applying doesn't collide with a
  previous snapshot name.
- `lifecycle { ignore_changes = [final_snapshot_identifier] }`: because that identifier
  contains `timestamp()`, it would be a *different string* on every single `plan`
  (timestamp() is re-evaluated each run), which would make Terraform think the resource
  needs to be updated/recreated every time for no real reason. Telling Terraform to ignore
  changes to just that one attribute stops that false-positive diff.

### Alerting on the database itself
```hcl
resource "aws_db_event_subscription" "this" {
  event_categories = ["availability","backup","failover","failure","low storage","maintenance","recovery"]
}

resource "aws_cloudwatch_metric_alarm" "free_storage_low" { threshold = 2 GiB, metric = FreeStorageSpace }
resource "aws_cloudwatch_metric_alarm" "high_cpu"        { threshold = 80%,  metric = CPUUtilization }
```
- `aws_db_event_subscription` taps into **RDS's own internal event stream** (failovers,
  backup completion/failure, low storage, etc.) — these are operational events, not metric
  thresholds, and they're pushed to the given SNS topic the moment they happen.
- The two CloudWatch alarms watch **metrics** (numeric time series) instead: if free disk
  drops below 2 GiB, or CPU stays above 80% for three consecutive 5-minute periods
  (`evaluation_periods = 3`, `period = 300`), SNS gets notified — both on alarm *and* when it
  recovers (`ok_actions`), so you know when the issue is resolved too.

## 5. `modules/rds_dr_replica/main.tf` — Cross-region disaster recovery

```hcl
resource "aws_kms_key" "dr" { ... }

resource "aws_db_instance" "replica" {
  replicate_source_db      = var.source_db_instance_arn
  storage_encrypted        = true
  kms_key_id               = aws_kms_key.dr.arn
  publicly_accessible      = false
  skip_final_snapshot      = true
  backup_retention_period  = 7
}
```
- `replicate_source_db` is what makes this a **read replica** rather than a standalone
  database: RDS continuously streams changes from the source instance (in the primary
  region) to this one (in the DR region) using MySQL's native replication under the hood,
  entirely managed by AWS.
- A **separate KMS key** is required here because KMS keys are regional — a key created in
  `us-east-1` cannot be used to encrypt a resource in `us-west-2`, so the DR module has to
  create and manage its own CMK in the DR region.
- `skip_final_snapshot = true` on the *replica* (not the primary) is intentional: this
  instance is disposable/re-creatable at any time by re-replicating from the source, so
  there's no unique data to protect when it's torn down — the source is still the source of
  truth until you actually promote the replica.
- `backup_retention_period = 7` is what's called out in the code comment: turning on
  automated backups *on the replica itself* means that the moment you promote it (breaking
  replication and making it a standalone writable primary), it already has its own backup
  history running, instead of starting from zero backup coverage right after a disaster.
- **Promotion is manual by design** — there's no Terraform resource or automation that
  calls `promote-read-replica`. Promoting a replica is an irreversible, high-impact action
  (it permanently breaks replication from the source), so it's left as an explicit AWS
  CLI/console runbook step a human decides to take during an actual regional outage,
  rather than something Terraform could accidentally trigger on a routine `apply`.

## 6. `modules/dynamodb/main.tf` — NoSQL session store

```hcl
resource "aws_kms_key" "dynamodb" { ... }

resource "aws_dynamodb_table" "this" {
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = var.hash_key
  range_key    = var.range_key

  attribute { name = var.hash_key,  type = "S" }
  attribute { name = var.range_key, type = "S" }

  ttl                      { attribute_name = var.ttl_attribute, enabled = true }
  point_in_time_recovery   { enabled = true }
  server_side_encryption   { enabled = true, kms_key_arn = aws_kms_key.dynamodb.arn }

  stream_enabled   = true
  stream_view_type = "NEW_AND_OLD_IMAGES"

  deletion_protection_enabled = true
}
```
- `billing_mode = PAY_PER_REQUEST` means you pay per read/write request instead of
  provisioning fixed read/write capacity units — appropriate for unpredictable or spiky
  session traffic, and it removes an entire class of capacity-planning/throttling risk for
  typical workloads (though see the alarm below — it can still happen).
- `hash_key`/`range_key` with `attribute` blocks define a **composite primary key**
  (`userId` + `sessionId` by default): DynamoDB only requires you to declare the *types* of
  attributes used in keys/indexes, not every attribute the table will ever store — that's
  the schemaless part of NoSQL.
- `ttl` on `expiresAt`: DynamoDB automatically deletes items once their `expiresAt`
  (epoch-seconds) timestamp is in the past, at no extra cost and without you writing any
  cleanup job — ideal for session data that should naturally expire.
- `point_in_time_recovery`: DynamoDB's equivalent of RDS's PITR — continuous backups
  allowing restore to any second in the last 35 days, without you managing a backup
  schedule.
- `server_side_encryption` with `kms_key_arn` pointed at a **customer-managed** key (rather
  than just `enabled = true`, which would use an AWS-owned key) — same reasoning as the RDS
  module: auditability and independent key lifecycle control.
- `stream_enabled` + `stream_view_type = NEW_AND_OLD_IMAGES`: turns on **DynamoDB Streams**,
  an ordered, near-real-time log of every item-level change (with both the before and after
  image of the item). This is what a Lambda function would subscribe to in order to react
  to session changes (e.g., audit logging, cache invalidation) — the table is already wired
  to support that even though the Lambda consumer isn't written yet.
- `deletion_protection_enabled = true`: DynamoDB's version of RDS's `deletion_protection` —
  blocks `terraform destroy`/console deletion until explicitly turned off first.

```hcl
resource "aws_cloudwatch_metric_alarm" "throttled_requests" {
  metric_name        = "ThrottledRequests"
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
}
```
- Alarms on **any** throttling event (`threshold = 0`, so even a single throttled request
  fires it). The code comment explains why this matters even on-demand billing: a single
  partition key receiving disproportionate traffic (a "hot partition") can still be
  throttled by DynamoDB's internal per-partition limits, regardless of overall table-level
  capacity mode. `treat_missing_data = "notBreaching"` ensures that *no data points*
  (i.e., no traffic at all) is correctly treated as "fine", not as an alarm condition.

---

## Key Concepts Recap

| Concept | Where used | Why it matters |
|---|---|---|
| Customer-managed KMS keys | RDS, DR replica, DynamoDB (3 separate keys) | Auditable, independently revocable encryption, vs. opaque AWS-owned keys |
| `manage_master_user_password` | RDS | Removes plaintext secrets from Terraform state entirely |
| Security-group-to-security-group ingress | RDS | Least-privilege network access, no CIDR ranges |
| `backup_retention_period` + PITR | RDS, DynamoDB | Recover to any point in time, not just to the last snapshot |
| `deletion_protection` | RDS, DynamoDB | Prevents accidental destroy via API/Terraform |
| `final_snapshot_identifier` + `lifecycle.ignore_changes` | RDS | Guarantees a last snapshot on deletion, without spurious diffs from `timestamp()` |
| Cross-region read replica | `rds_dr_replica` | Survives a full regional AWS outage; promotion is a deliberate manual step |
| DynamoDB Streams | `dynamodb` | Enables future event-driven consumers (Lambda) without a schema change later |
| `aws.dr` provider alias | `providers.tf`, `versions.tf` | The mechanism for one Terraform run to manage two AWS regions safely |
| `default_tags` | `providers.tf` | Consistent tagging for cost allocation/audit without repeating `tags {}` per resource |

See [README.md](./README.md) for the still-missing root `main.tf`, backup-automation Lambda,
and other gaps needed before this is a fully wired, deployable stack.
