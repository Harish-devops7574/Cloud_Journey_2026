"""Scheduled on-demand backup automation for RDS and DynamoDB.

Creates a manual RDS snapshot and an on-demand DynamoDB backup, then prunes
any manual backups older than RETENTION_DAYS. Automated RDS backups / DynamoDB
PITR are handled separately by the service itself (see modules/rds,
modules/dynamodb) - this Lambda only manages the *additional* on-demand
backups requested in Week 3's design (manual_snapshot_retention_days).
"""
import os
import datetime
import boto3

rds = boto3.client("rds")
dynamodb = boto3.client("dynamodb")
sns = boto3.client("sns")

DB_INSTANCE_IDENTIFIER = os.environ["DB_INSTANCE_IDENTIFIER"]
DYNAMODB_TABLE_NAME = os.environ["DYNAMODB_TABLE_NAME"]
SNS_TOPIC_ARN = os.environ["SNS_TOPIC_ARN"]
RETENTION_DAYS = int(os.environ.get("RETENTION_DAYS", "14"))

TIMESTAMP_FMT = "%Y%m%d%H%M%S"


def _snapshot_id():
    stamp = datetime.datetime.utcnow().strftime(TIMESTAMP_FMT)
    return f"{DB_INSTANCE_IDENTIFIER}-manual-{stamp}"


def _backup_name():
    stamp = datetime.datetime.utcnow().strftime(TIMESTAMP_FMT)
    return f"{DYNAMODB_TABLE_NAME}-manual-{stamp}"


def create_rds_snapshot():
    snapshot_id = _snapshot_id()
    rds.create_db_snapshot(
        DBSnapshotIdentifier=snapshot_id,
        DBInstanceIdentifier=DB_INSTANCE_IDENTIFIER,
    )
    return snapshot_id


def create_dynamodb_backup():
    response = dynamodb.create_backup(
        TableName=DYNAMODB_TABLE_NAME,
        BackupName=_backup_name(),
    )
    return response["BackupDetails"]["BackupArn"]


def prune_rds_snapshots():
    cutoff = datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(days=RETENTION_DAYS)
    paginator = rds.get_paginator("describe_db_snapshots")
    deleted = []
    for page in paginator.paginate(DBInstanceIdentifier=DB_INSTANCE_IDENTIFIER, SnapshotType="manual"):
        for snapshot in page["DBSnapshots"]:
            if snapshot["SnapshotCreateTime"] < cutoff:
                rds.delete_db_snapshot(DBSnapshotIdentifier=snapshot["DBSnapshotIdentifier"])
                deleted.append(snapshot["DBSnapshotIdentifier"])
    return deleted


def prune_dynamodb_backups():
    cutoff = datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(days=RETENTION_DAYS)
    deleted = []
    paginator = dynamodb.get_paginator("list_backups")
    for page in paginator.paginate(TableName=DYNAMODB_TABLE_NAME, BackupType="USER"):
        for backup in page["BackupSummaries"]:
            if backup["BackupCreationDateTime"] < cutoff:
                dynamodb.delete_backup(BackupArn=backup["BackupArn"])
                deleted.append(backup["BackupArn"])
    return deleted


def notify(subject, message):
    sns.publish(TopicArn=SNS_TOPIC_ARN, Subject=subject[:100], Message=message)


def handler(event, context):
    results = {}
    errors = []

    try:
        results["rds_snapshot_id"] = create_rds_snapshot()
    except Exception as exc:  # noqa: BLE001 - report all failures, don't abort pruning
        errors.append(f"RDS snapshot failed: {exc}")

    try:
        results["dynamodb_backup_arn"] = create_dynamodb_backup()
    except Exception as exc:  # noqa: BLE001
        errors.append(f"DynamoDB backup failed: {exc}")

    try:
        results["pruned_rds_snapshots"] = prune_rds_snapshots()
    except Exception as exc:  # noqa: BLE001
        errors.append(f"RDS snapshot pruning failed: {exc}")

    try:
        results["pruned_dynamodb_backups"] = prune_dynamodb_backups()
    except Exception as exc:  # noqa: BLE001
        errors.append(f"DynamoDB backup pruning failed: {exc}")

    if errors:
        notify(
            f"[FAILURE] Backup automation for {DB_INSTANCE_IDENTIFIER}",
            "Some backup steps failed:\n" + "\n".join(errors) + f"\n\nCompleted steps: {results}",
        )
        raise RuntimeError("; ".join(errors))

    notify(
        f"[SUCCESS] Backup automation for {DB_INSTANCE_IDENTIFIER}",
        f"All backup steps completed:\n{results}",
    )
    return results
