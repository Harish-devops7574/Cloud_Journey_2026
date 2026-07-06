provider "aws" {
  region = var.aws_region
}

# S3 Bucket
resource "aws_s3_bucket" "lab_bucket" {
  bucket        = var.bucket_name
  force_destroy = true
}

resource "aws_s3_bucket_versioning" "lab_bucket_versioning" {
  bucket = aws_s3_bucket.lab_bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_public_access_block" "lab_bucket_block" {
  bucket                  = aws_s3_bucket.lab_bucket.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# IAM Role
resource "aws_iam_role" "ec2_s3_role" {
  name = "ec2-s3-access-role-tf"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "s3_policy_attach" {
  role       = aws_iam_role.ec2_s3_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
}

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "ec2-instance-profile-tf"
  role = aws_iam_role.ec2_s3_role.name
}

# Security Group
resource "aws_security_group" "ec2_sg" {
  name        = "ec2-lab-sg-tf"
  description = "Allow SSH and HTTP"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# EC2 Instance
resource "aws_instance" "lab_ec2" {
  ami                    = "ami-0c02fb55956c7d316"
  instance_type          = "t2.micro"
  key_name               = var.key_pair_name
  security_groups        = [aws_security_group.ec2_sg.name]
  iam_instance_profile   = aws_iam_instance_profile.ec2_profile.name
  user_data              = file("userdata.sh")

  tags = {
    Name = "lab-ec2-tf"
  }
}
