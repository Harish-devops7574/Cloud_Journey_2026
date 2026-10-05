# Week 3 — Database, Backup & Disaster Recovery (Terraform)

Production-oriented Terraform for an RDS MySQL + DynamoDB data tier with encryption,
automated backups, point-in-time recovery, and cross-region disaster recovery.

## Current State of This Code

This root currently holds shared configuration (`providers.tf`, `variables.tf`, `versions.tf`)
and three self-contained modules. **There is no root `main.tf` wiring the modules together yet**
— each module is deployable on its own but needs a root module to pass module outputs
between them (e.g., RDS ARN → DR replica, SNS topic ARN → RDS/DynamoDB alarms). See
[Gaps & Next Steps](#gaps--next-steps) before running `terraform apply`.

## Layout

```
week3-db-backup-dr/
├── providers.tf              # aws (primary) + aws.dr (secondary region) providers, default_tags
├── variables.tf               # all root input variables (region, VPC, RDS, DynamoDB, backup automation)
├── versions.tf                # Terraform >=1.7, aws ~>5.40, random ~>3.6, archive ~>2.4; commented S3 backend
└── modules/
    ├── rds/                   # Primary MySQL instance
    ├── rds_dr_replica/        # Cross-region encrypted read replica
    └── dynamodb/              # UserSessions-style table
```

## Module: `modules/rds`

Provisions the primary relational database.

**Resources**
- `aws_kms_key` / `aws_kms_alias` — customer-managed key dedicated to this database (storage + Performance Insights), with automatic key rotation enabled.
- `aws_db_subnet_group` — built from `private_subnet_ids`.
- `aws_security_group` + `aws_security_group_rule` (`for_each` over `app_security_group_ids`) — ingress on port 3306 is only granted to explicitly approved security groups; no CIDR-based rules exist.
- `aws_db_parameter_group` (family `mysql8.0`) — enforces `require_secure_transport = 1`, i.e. clients must connect over TLS.
- `aws_db_instance` —
  - `storage_encrypted = true` using the module's own KMS key
  - `manage_master_user_password = true` → **AWS-managed Secrets Manager password, never a Terraform variable or state value**
  - `multi_az`, `backup_retention_period`, `deletion_protection` all driven by root variables
  - `enabled_cloudwatch_logs_exports = ["error", "general", "slowquery"]`
  - `performance_insights_enabled = true`, encrypted with the same KMS key
  - `skip_final_snapshot = false` with a timestamped `final_snapshot_identifier` (ignored on subsequent applies via `lifecycle.ignore_changes` so Terraform doesn't want to recreate the instance every run)
  - `publicly_accessible = false` (hardcoded — not configurable)
- `aws_db_event_subscription` — forwards `availability`, `backup`, `failover`, `failure`, `low storage`, `maintenance`, `recovery` events to an SNS topic.
- `aws_cloudwatch_metric_alarm` × 2 — `FreeStorageSpace < 2 GiB` and `CPUUtilization > 80%` for 15 minutes, both notifying the same SNS topic on alarm and OK.

**Inputs** (all required unless noted): `project_name`, `environment`, `vpc_id`, `private_subnet_ids`,
`app_security_group_ids` (default `[]`), `engine_version`, `instance_class`, `allocated_storage`,
`max_allocated_storage`, `db_name`, `master_username`, `backup_retention_period`, `multi_az`,
`deletion_protection`, `sns_topic_arn`.

**Outputs**: `db_instance_id`, `db_instance_arn`, `endpoint`, `master_user_secret_arn`
(Secrets Manager ARN for the auto-managed password), `security_group_id`, `kms_key_arn`.

## Module: `modules/rds_dr_replica`

Cross-region disaster recovery via a native RDS cross-region read replica (not a snapshot copy).

**Resources**
- `aws_kms_key` / `aws_kms_alias` — separate CMK in the DR region (KMS keys are regional).
- `aws_db_instance.replica` — `replicate_source_db = var.source_db_instance_arn`, encrypted with the DR-region key, `publicly_accessible = false`, `backup_retention_period = 7` (the replica keeps its own backup history so a promoted instance is immediately protected).
- `skip_final_snapshot = true` on the replica itself (it's disposable until promoted).

**To fail over**: promote the replica out-of-band —
```bash
aws rds promote-read-replica --db-instance-identifier <replica-id> --region <dr_region>
```
This module does not automate promotion; that is a manual/runbook step by design (avoids
Terraform accidentally triggering a failover).

**Inputs**: `source_db_instance_arn`, `identifier`, `instance_class`, `kms_key_alias`.
**Outputs**: `replica_id`, `replica_endpoint`.

**Wiring note**: cross-region read replicas require the source DB's automated backups to
be enabled (they already are, via `backup_retention_period`) and the replica must be
created with the `aws.dr` provider alias, e.g. `providers = { aws = aws.dr }` in the module block.

## Module: `modules/dynamodb`

**Resources**
- `aws_kms_key` / `aws_kms_alias` — table-specific CMK.
- `aws_dynamodb_table` —
  - `billing_mode = PAY_PER_REQUEST` (no capacity planning required)
  - Composite key: `hash_key` + `range_key` (both type `S`)
  - `ttl` on `var.ttl_attribute` for automatic item expiry
  - `point_in_time_recovery.enabled = true`
  - `server_side_encryption` with the module's CMK (not the AWS-owned default key)
  - `stream_enabled = true`, `stream_view_type = "NEW_AND_OLD_IMAGES"` (ready for Lambda triggers)
  - `deletion_protection_enabled = true`
- `aws_cloudwatch_metric_alarm.throttled_requests` — alarms on **any** `ThrottledRequests > 0`, even under on-demand billing, since hot partitions can still throttle.

**Inputs**: `table_name`, `hash_key`, `range_key`, `ttl_attribute`, `sns_topic_arn`.
**Outputs**: none defined yet — add `table_arn`, `table_stream_arn`, and `table_name` outputs
if downstream Lambdas (e.g., the backup automation function) need to reference this table.

## Root Variables Reference (`variables.tf`)

| Variable | Default | Purpose |
|---|---|---|
| `aws_region` | `us-east-1` | Primary region |
| `dr_region` | `us-west-2` | DR region (secondary provider alias `aws.dr`) |
| `project_name` | `webapp` | Naming/tag prefix |
| `environment` | `dev` | Validated: `dev`\|`staging`\|`prod` |
| `owner` | `platform-team` | Tag only |
| `vpc_id` | — (required) | Existing VPC; this project does **not** create a VPC |
| `private_subnet_ids` | — (required) | Validated: ≥ 2 subnets for Multi-AZ |
| `app_security_group_ids` | `[]` | SGs allowed to reach RDS on 3306 |
| `db_engine_version` | `8.0.35` | MySQL version |
| `db_instance_class` | `db.t3.micro` | RDS sizing |
| `db_allocated_storage` / `db_max_allocated_storage` | `20` / `100` | Storage + autoscaling ceiling |
| `db_name` | `webapp` | Initial schema |
| `db_master_username` | `admin` | Password is Secrets-Manager managed, not a variable |
| `db_backup_retention_period` | `7` | Validated: 1–35 days |
| `db_multi_az` | `false` | Set `true` for prod |
| `db_deletion_protection` | `false` | Set `true` for prod |
| `enable_cross_region_dr` | `false` | Root-level flag; must be consumed by a root `main.tf` to conditionally create `modules/rds_dr_replica` |
| `dynamodb_table_name` | `UserSessions` | Table name |
| `dynamodb_hash_key` / `dynamodb_range_key` | `userId` / `sessionId` | Composite key |
| `dynamodb_ttl_attribute` | `expiresAt` | TTL field |
| `backup_schedule_expression` | `cron(0 3 * * ? *)` | For the (not-yet-implemented) backup-automation Lambda's EventBridge rule |
| `manual_snapshot_retention_days` | `14` | Retention for on-demand snapshots taken by the automation Lambda |
| `notification_email` | `""` | Optional SNS email subscription |
| `log_retention_days` | `30` | Lambda CloudWatch Logs retention |

## Providers & Versions

- `versions.tf` pins `terraform >= 1.7.0`, `hashicorp/aws ~> 5.40`, `hashicorp/random ~> 3.6`,
  `hashicorp/archive ~> 2.4` (the `archive` provider implies a Lambda deployment package is
  expected — see gaps below).
- `providers.tf` configures the default `aws` provider plus an aliased `aws.dr` provider for
  `var.dr_region`, both applying consistent `default_tags` (`Project`, `Environment`, `ManagedBy`,
  `Owner`, and `Purpose = disaster-recovery` on the DR provider).
- The S3 remote-state backend block in `versions.tf` is present but **commented out** — must be
  filled in with a real bucket/DynamoDB lock table name before team use.

## Gaps & Next Steps (to reach full production readiness)

1. **Root `main.tf`** — instantiate `module "rds"`, conditionally `module "rds_dr_replica"`
   (`count = var.enable_cross_region_dr ? 1 : 0`, `providers = { aws = aws.dr }`), and
   `module "dynamodb"`, wiring an SNS topic (`aws_sns_topic` + optional email subscription
   from `var.notification_email`) into all three.
2. **Backup automation Lambda** — `versions.tf` already requires the `archive` provider,
   implying a `data "archive_file"` + `aws_lambda_function` + `aws_cloudwatch_event_rule`
   (using `var.backup_schedule_expression`) + `aws_lambda_permission` are still needed. This
   Lambda should create on-demand RDS/DynamoDB backups, prune anything older than
   `var.manual_snapshot_retention_days`, and publish results to the SNS topic.
3. **Remote state backend** — uncomment and fill in the `backend "s3"` block in `versions.tf`.
4. **Root outputs.tf** — expose `db_endpoint`, `db_master_user_secret_arn`, `dynamodb_table_name`,
   `dr_replica_endpoint` (conditional) for use by the Week 4 serverless API layer.
5. **DynamoDB module outputs** — add `table_arn` / `table_stream_arn` so other modules (e.g. a
   Lambda consuming the stream) can reference this table without hardcoding ARNs.
6. **CI validation** — add `terraform fmt -check`, `terraform validate`, and `tflint`/`checkov`
   to a pipeline before merge.

## How to Deploy (once the root `main.tf` above is added)

```bash
cd week3-db-backup-dr
terraform init
terraform plan \
  -var="vpc_id=vpc-xxxxxxxx" \
  -var='private_subnet_ids=["subnet-aaa","subnet-bbb"]' \
  -var="environment=prod" \
  -var="db_multi_az=true" \
  -var="db_deletion_protection=true" \
  -var="enable_cross_region_dr=true"
terraform apply
```

No database password is ever passed on the CLI — RDS generates and rotates it in Secrets
Manager automatically (`manage_master_user_password = true`).

## Security Summary

✅ Storage-level encryption via dedicated, rotating KMS CMKs (RDS, DR replica, DynamoDB — three separate keys)
✅ TLS enforced at the database (`require_secure_transport`)
✅ No public accessibility on either RDS instance
✅ Security-group-scoped ingress only (no CIDR rules)
✅ Master password fully managed by AWS Secrets Manager, never in Terraform state as plaintext
✅ PITR enabled on both RDS (via backup retention) and DynamoDB
✅ CloudWatch alarms wired to SNS for storage, CPU, and DynamoDB throttling
✅ `deletion_protection` available (must be turned on for prod via variables)
