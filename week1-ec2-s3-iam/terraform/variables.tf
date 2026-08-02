variable "aws_region" {
  type        = string
  description = "AWS region to deploy resources"
  default     = "us-east-1"
}

variable "bucket_name" {
  type        = string
  description = "Name of the S3 bucket"
  default     = "john-aws-lab-bucket-tf"
}

variable "key_pair_name" {
  type        = string
  description = "Your existing EC2 key pair name"
  default     = "tf-lab-key"
}

variable "instance_type" {
  type        = string
  description = "EC2 instance type"
  default     = "t2.micro"
}

variable "my_ip" {
  type        = string
  description = "Your IP address for SSH and HTTP access"
  default     = "0.0.0.0/0"
}
