############################################
# main.tf
############################################

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

############################################
# Locals (SSM Parameter names)
############################################

locals {
  ssm_db_host_name = "/${var.project_name}/db/host"
  ssm_db_port_name = "/${var.project_name}/db/port"
  ssm_db_name_name = "/${var.project_name}/db/name"
}


############################################
# Data
############################################

data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

############################################
# Networking: VPC & IGW
############################################

resource "aws_vpc" "lab" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.project_name}-vpc"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.lab.id

  tags = {
    Name = "${var.project_name}-igw"
  }
}


############################################
# Subnets: Public & Private
############################################

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.lab.id
  cidr_block              = var.public_subnet_cidr
  availability_zone       = var.az_a
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project_name}-public-subnet"
  }
}

resource "aws_subnet" "private_a" {
  vpc_id            = aws_vpc.lab.id
  cidr_block        = var.private_subnet_a_cidr
  availability_zone = var.az_a

  tags = {
    Name = "${var.project_name}-private-a"
  }
}

resource "aws_subnet" "private_b" {
  vpc_id            = aws_vpc.lab.id
  cidr_block        = var.private_subnet_b_cidr
  availability_zone = var.az_b

  tags = {
    Name = "${var.project_name}-private-b"
  }
}

############################################
# Route Tables
############################################

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.lab.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "${var.project_name}-public-rt"
  }
}

resource "aws_route_table_association" "public_assoc" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

############################################
# Security Groups
############################################

resource "aws_security_group" "ec2" {
  name        = "${var.project_name}-sg-ec2"
  description = "Allow HTTP inbound; optional SSH; allow all egress"
  vpc_id      = aws_vpc.lab.id

  # HTTP for browser testing
  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = var.allowed_http_cidrs
  }

  # SSH (disabled by default)
  dynamic "ingress" {
    for_each = var.enable_ssh ? [1] : []
    content {
      description = "SSH"
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      cidr_blocks = var.ssh_allowed_cidrs
    }
  }

  # Outbound to anywhere (needed for yum/pip, AWS APIs, etc.)
  egress {
    description = "All egress"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-sg-ec2"
  }
}

resource "aws_security_group" "rds" {
  name        = "${var.project_name}-sg-rds"
  description = "Allow MySQL inbound ONLY from EC2 SG"
  vpc_id      = aws_vpc.lab.id

  ingress {
    description     = "MySQL from EC2 SG only"
    from_port       = var.db_port
    to_port         = var.db_port
    protocol        = "tcp"
    security_groups = [aws_security_group.ec2.id]
  }

  # (Optional) egress not required for SG to function, but leaving default behavior
  egress {
    description = "All egress"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-sg-rds"
  }
}

############################################
# RDS (Private)
############################################

resource "aws_db_subnet_group" "lab" {
  name       = "${var.project_name}-db-subnet-group"
  subnet_ids = [aws_subnet.private_a.id, aws_subnet.private_b.id]

  tags = {
    Name = "${var.project_name}-db-subnet-group"
  }
}

resource "aws_db_instance" "mysql" {
  identifier        = var.db_identifier
  engine            = "mysql"
  engine_version    = var.db_engine_version
  instance_class    = var.db_instance_class
  allocated_storage = var.db_allocated_storage
  username          = var.db_username
  password          = var.db_password
  port              = var.db_port

  db_subnet_group_name   = aws_db_subnet_group.lab.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false

  # Lab settings (not production)
  skip_final_snapshot = true
  deletion_protection = false

  tags = {
    Name = "${var.project_name}-rds"
  }
}

############################################
# SSM Parameter Store (DB values)
############################################

resource "aws_ssm_parameter" "db_host" {
  name  = local.ssm_db_host_name
  type  = "String"
  value = aws_db_instance.mysql.address

  tags = {
    Name = "${var.project_name}-ssm-db-host"
  }
}

resource "aws_ssm_parameter" "db_port" {
  name  = local.ssm_db_port_name
  type  = "String"
  value = tostring(var.db_port)

  tags = {
    Name = "${var.project_name}-ssm-db-port"
  }
}

resource "aws_ssm_parameter" "db_name" {
  name  = local.ssm_db_name_name
  type  = "String"
  value = var.db_name

  tags = {
    Name = "${var.project_name}-ssm-db-name"
  }
}


#######################################
# Secrets Manager (DB connection info)
#######################################

resource "aws_secretsmanager_secret" "db" {
  name                    = var.secret_name
  recovery_window_in_days = 0

  tags = {
    Name = "${var.project_name}-db-secret"
  }
}

resource "aws_secretsmanager_secret_version" "db" {
  secret_id = aws_secretsmanager_secret.db.id

  secret_string = jsonencode({
    username = var.db_username
    password = var.db_password
  })
}

############################################
# CloudWatch Logs (Centralized logging)
############################################

resource "aws_cloudwatch_log_group" "app" {
  name              = "/${var.project_name}/app"
  retention_in_days = 7

  tags = {
    Name = "${var.project_name}-app-logs"
  }
}

####################################################################################
# IAM Role + Instance Profile for EC2 to read secret + SSM params + Cloud watch Logs
####################################################################################

resource "aws_iam_role" "ec2_role" {
  name = "${var.project_name}-ec2-secrets-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect    = "Allow",
      Principal = { Service = "ec2.amazonaws.com" },
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "secrets_read" {
  name = "${var.project_name}-secrets-ssm-cwlogs"
  role = aws_iam_role.ec2_role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      #Secrets Manager (DB credentials)
      {
        Sid      = "ReadDBSecret",
        Effect   = "Allow",
        Action   = ["secretsmanager:GetSecretValue"],
        Resource = aws_secretsmanager_secret.db.arn
      },

      #SSM Parameter Store (DB host / port / name)
      {
        Sid    = "ReadDBParams",
        Effect = "Allow",
        Action = ["ssm:GetParameter", "ssm:GetParameters"],
        Resource = [
          aws_ssm_parameter.db_host.arn,
          aws_ssm_parameter.db_port.arn,
          aws_ssm_parameter.db_name.arn
        ]
      },

      #CloudWatch Logs (centralized logging)
      {
        Sid    = "WriteCloudWatchLogs",
        Effect = "Allow",
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams",
          "logs:DescribeLogGroups"
        ],
        Resource = [
          aws_cloudwatch_log_group.app.arn,
          "${aws_cloudwatch_log_group.app.arn}:*"
        ]
      }
    ]
  })
}

resource "aws_iam_instance_profile" "ec2" {
  name = "${var.project_name}-ec2-instance-profile"
  role = aws_iam_role.ec2_role.name
}

############################################
# CloudWatch Metric Filter (detect DB failures)
############################################

resource "aws_cloudwatch_log_metric_filter" "db_connect_failures" {
  name           = "${var.project_name}-db-connect-failures"
  log_group_name = aws_cloudwatch_log_group.app.name
  pattern        = "DB_CONNECT_FAIL"

  metric_transformation {
    name      = "DBConnectFailures"
    namespace = "${var.project_name}/App"
    value     = "1"
  }
}

############################################
#SNS Topic
############################################

resource "aws_sns_topic" "db_alerts" {
  name = "${var.project_name}-db-alerts"
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.db_alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

############################################
# CloudWatch Alarm (fires on DB_CONNECT_FAIL)
############################################

resource "aws_cloudwatch_metric_alarm" "db_connect_fail_alarm" {
  alarm_name          = "${var.project_name}-db-connect-failure-alarm"
  alarm_description   = "Triggers when DB connection failures are detected"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  period              = 60
  threshold           = 1
  statistic           = "Sum"

  namespace   = "${var.project_name}/App"
  metric_name = "DBConnectFailures"

  treat_missing_data = "notBreaching"

  alarm_actions = [
    aws_sns_topic.db_alerts.arn
    
  ]

  depends_on = [
  aws_cloudwatch_log_metric_filter.db_connect_failures
]
}

############################################
# EC2 Web App
############################################

resource "aws_instance" "app" {
  ami                    = data.aws_ami.al2023.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.ec2.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2.name

  # Only set key_name if enable_ssh is true and key_name is provided
  key_name = var.key_name

  user_data                   = file("user_data.sh")
  user_data_replace_on_change = true

  tags = {
    Name = "${var.project_name}-ec2-app"
  }

  depends_on = [
    aws_secretsmanager_secret_version.db,
    aws_ssm_parameter.db_host,
    aws_ssm_parameter.db_port,
    aws_ssm_parameter.db_name
  ]
}
