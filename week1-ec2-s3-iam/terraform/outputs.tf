output "ec2_public_ip" {
  value = aws_instance.lab_ec2.public_ip
}

output "s3_bucket_name" {
  value = aws_s3_bucket.lab_bucket.bucket
}

output "iam_role_name" {
  value = aws_iam_role.ec2_s3_role.name
}
