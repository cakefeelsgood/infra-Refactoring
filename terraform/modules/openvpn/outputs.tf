output "instance_id" {
  description = "OpenVPN EC2 instance ID."
  value       = aws_instance.this.id
}

output "private_ip" {
  description = "OpenVPN EC2 private IP."
  value       = aws_instance.this.private_ip
}


output "primary_network_interface_id" {
  description = "Primary network interface ID of the OpenVPN EC2 instance."
  value       = aws_instance.this.primary_network_interface_id
}


output "public_ip" {
  description = "OpenVPN public IP. Elastic IP is preferred when enabled."
  value       = var.enable_eip ? aws_eip.this[0].public_ip : aws_instance.this.public_ip
}

output "public_dns" {
  description = "OpenVPN EC2 public DNS."
  value       = aws_instance.this.public_dns
}

output "eip_allocation_id" {
  description = "OpenVPN Elastic IP allocation ID."
  value       = try(aws_eip.this[0].id, null)
}

output "client_config_path" {
  description = "Generated OpenVPN client profile path on the instance."
  value       = "/home/ec2-user/${var.client_name}.ovpn"
}

output "client_profile_secret_name" {
  description = "Secrets Manager secret name that stores the generated OpenVPN client profile."
  value       = var.client_profile_secret_name
}

output "client_profile_secret_arn" {
  description = "Secrets Manager secret ARN that stores the generated OpenVPN client profile."
  value       = var.client_profile_secret_arn
}
