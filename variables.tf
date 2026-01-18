############################################
# variables.tf
############################################

variable "project_name" {
  description = "Name prefix for resources (tags, identifiers)."
  type        = string
  default     = "bmbf_arm_lab"
}

variable "aws_region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "us-east-1"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.215.0.0/16"
}

variable "public_subnet_cidr" {
  description = "CIDR block for the public subnet (EC2)."
  type        = string
  default     = "10.215.1.0/24"
}

variable "private_subnet_a_cidr" {
  description = "CIDR block for private subnet A (RDS)."
  type        = string
  default     = "10.215.11.0/24"
}

variable "private_subnet_b_cidr" {
  description = "CIDR block for private subnet B (RDS)."
  type        = string
  default     = "10.215.12.0/24"
}

variable "az_a" {
  description = "Availability Zone for subnet A."
  type        = string
  default     = "us-east-1a"
}

variable "az_b" {
  description = "Availability Zone for subnet B."
  type        = string
  default     = "us-east-1b"
}

variable "instance_type" {
  description = "EC2 instance type for the Flask app server."
  type        = string
  default     = "t3.micro"
}

variable "allowed_http_cidrs" {
  description = "CIDR blocks allowed to reach the web app over HTTP (port 80)."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "enable_ssh" {
  description = "Whether to allow SSH inbound to the EC2 instance."
  type        = bool
  default     = true
}

variable "ssh_allowed_cidrs" {
  description = "CIDR blocks allowed to SSH into EC2 (only used if enable_ssh=true)."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "key_name" {
  description = "Optional EC2 key pair name for SSH access (required if enable_ssh=true)."
  type        = string
  default     = "bmbfuniversity"
}

variable "db_identifier" {
  description = "RDS instance identifier."
  type        = string
  default     = "lab-mysql"
}

variable "db_name" {
  description = "Initial database name to create/use in the app."
  type        = string
  default     = "notes"
}

variable "db_username" {
  description = "Master username for the RDS MySQL instance."
  type        = string
  default     = "admin"
}

variable "db_password" {
  description = "Master password for the RDS MySQL instance (store securely; do not commit)."
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.db_password) >= 8
    error_message = "db_password must be at least 8 characters."
  }
}

variable "db_engine_version" {
  description = "MySQL engine version."
  type        = string
  default     = "8.0"
}

variable "db_instance_class" {
  description = "RDS instance class."
  type        = string
  default     = "db.t3.micro"
}

variable "db_allocated_storage" {
  description = "Allocated storage (GiB) for the RDS instance."
  type        = number
  default     = 20
}

variable "db_port" {
  description = "MySQL port."
  type        = number
  default     = 3306
}

variable "secret_name" {
  description = "Secrets Manager secret name for DB credentials."
  type        = string
  default     = "lab/rds/mysql"
}

variable "alert_email" {
  description = "Email address to receive CloudWatch alarms"
  type        = string
  default = "iknowcloud2+snstrigger@gmail.com"
}

