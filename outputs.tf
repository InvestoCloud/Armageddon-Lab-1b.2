output "ec2_public_ip" {
  value = aws_instance.app.public_ip
}

output "ec2_public_dns" {
  value = aws_instance.app.public_dns
}

output "ec2_instance_id" {
  value       = aws_instance.app.id
  description = "EC2 instance ID"
}

output "ec2_role_name" {
  value       = aws_iam_role.ec2_role.name
  description = "IAM role name attached to EC2"
}

output "ec2_security_group_id" {
  value       = aws_security_group.ec2.id
  description = "EC2 security group ID"
}

output "rds_security_group_id" {
  value       = aws_security_group.rds.id
  description = "RDS security group ID"
}

output "rds_identifier" {
  value       = aws_db_instance.mysql.id
  description = "RDS DB instance identifier"
}

output "rds_endpoint" {
  value       = aws_db_instance.mysql.address
  description = "RDS endpoint address (should match SSM host value)"
}

output "secret_id" {
  value       = aws_secretsmanager_secret.db.id
  description = "Secrets Manager secret ID (credentials only)"
}

output "ssm_db_host_param_name" {
  value       = aws_ssm_parameter.db_host.name
  description = "SSM parameter name for DB host"
}

output "ssm_db_port_param_name" {
  value       = aws_ssm_parameter.db_port.name
  description = "SSM parameter name for DB port"
}

output "ssm_db_name_param_name" {
  value       = aws_ssm_parameter.db_name.name
  description = "SSM parameter name for DB name"
}
