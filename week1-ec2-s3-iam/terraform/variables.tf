variable "aws_region" {
  default = "us-east-1"
}

variable "bucket_name" {
  default = "harish-aws-lab-bucket-tf"
}

variable "key_pair_name" {
  description = "Your existing EC2 key pair name"
  default     = "tf-lab-key"
}


###
# Add types of the varible for each declaration. 

#EG 

# variable "key_pair_name" {
#   description = "Your existing EC2 key pair name"/
#    type = string
#   default     = "tf-lab-key"
# }