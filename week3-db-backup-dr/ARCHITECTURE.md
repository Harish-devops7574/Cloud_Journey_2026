# Week 3 — Architecture Diagram

```mermaid
graph TB
    subgraph VPC["Existing VPC (bring-your-own)"]
        subgraph Subnets["Private Subnets (2+ AZs)"]
            RDS[("RDS MySQL\ndb.t3.micro\nStorage encrypted")]
        end
        SG["Security Group\nIngress: 3306 from\napp_security_group_ids only"]
    end

    KMS1["KMS Key\n(RDS CMK)"]
    KMS2["KMS Key\n(DynamoDB CMK)"]
    SM["Secrets Manager\n(auto-managed master password)"]
    PG["DB Parameter Group\nrequire_secure_transport=1\n(skipped in restricted mode)"]

    DDB[("DynamoDB Table\nUserSessions\nPITR + Streams")]

    SNS["SNS Topic\nweek3lab-dev-db-alerts"]
    CW1["CloudWatch Alarm\nFreeStorageSpace < 2GiB"]
    CW2["CloudWatch Alarm\nCPUUtilization > 80%"]
    CW3["CloudWatch Alarm\nDynamoDB Throttled Requests"]
    EVT["RDS Event Subscription\n(failover, backup, failure...)"]

    LAMBDA["Backup Automation Lambda\n(optional - needs iam:PassRole)\nmanual snapshots + pruning"]
    EB["EventBridge Schedule\ncron(0 3 * * ? *)"]

    DR["Cross-Region DR Replica\n(optional, aws.dr provider)\nus-west-2"]

    RDS -->|encrypted by| KMS1
    RDS -->|password stored in| SM
    RDS -.->|hardens TLS| PG
    RDS --- SG
    DDB -->|encrypted by| KMS2

    RDS --> EVT --> SNS
    CW1 --> SNS
    CW2 --> SNS
    CW3 --> SNS

    EB -.->|triggers| LAMBDA
    LAMBDA -.->|snapshots| RDS
    LAMBDA -.->|backups| DDB
    LAMBDA -.->|notifies| SNS

    RDS -.->|promote on failover| DR

    style LAMBDA stroke-dasharray: 5 5
    style DR stroke-dasharray: 5 5
    style PG stroke-dasharray: 5 5
```

**Key points:**
- **Solid lines** = always deployed; **dashed lines/boxes** = optional, gated by variables (`enable_backup_automation`, `enable_cross_region_dr`, and the parameter group which is skipped under `restricted_permissions`).
- Both RDS and DynamoDB get dedicated KMS keys (not the AWS-managed default), and the RDS master password is never in Terraform state — it's auto-generated and stored in Secrets Manager.
- All alarms/events funnel into a single shared SNS topic, which is what the (optional) backup Lambda also publishes success/failure notifications to.
- The DR replica uses a second aliased provider (`aws.dr`) pointed at a different region, only created when explicitly enabled.
