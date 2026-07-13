provider "aws" {
  region = var.aws_region
}

resource "aws_cloudwatch_dashboard" "harish_dashboard" {
  dashboard_name = "harish-week2-dashboard-tf"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6
        properties = {
          title   = "Harish EC2 CPU Utilization"
          region  = "us-east-1"
          metrics = [
            ["AWS/EC2", "CPUUtilization", "InstanceId", var.instance_id]
          ]
          period = 300
          stat   = "Average"
          view   = "timeSeries"
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6
        properties = {
          title   = "Harish EC2 Network In/Out"
          region  = "us-east-1"
          metrics = [
            ["AWS/EC2", "NetworkIn", "InstanceId", var.instance_id],
            ["AWS/EC2", "NetworkOut", "InstanceId", var.instance_id]
          ]
          period = 300
          stat   = "Average"
          view   = "timeSeries"
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 12
        height = 6
        properties = {
          title   = "Harish S3 Bucket Size"
          region  = "us-east-1"
          metrics = [
            ["AWS/S3", "BucketSizeBytes", "BucketName", var.bucket_name, "StorageType", "StandardStorage"]
          ]
          period = 86400
          stat   = "Average"
          view   = "timeSeries"
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 6
        width  = 12
        height = 6
        properties = {
          title   = "Harish Custom App Metrics - Error Count"
          region  = "us-east-1"
          metrics = [
            ["HarishApp", "ErrorCount"],
            ["HarishApp", "ResponseTime"]
          ]
          period = 300
          stat   = "Sum"
          view   = "timeSeries"
        }
      }
    ]
  })
}
