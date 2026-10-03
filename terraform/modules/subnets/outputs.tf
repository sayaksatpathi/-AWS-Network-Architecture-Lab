output "public_subnet_ids" {
  description = "IDs of public subnets"
  value       = aws_subnet.public[*].id
}

output "private_app_subnet_ids" {
  description = "IDs of private application subnets"
  value       = aws_subnet.private_app[*].id
}

output "private_db_subnet_ids" {
  description = "IDs of private database subnets"
  value       = aws_subnet.private_db[*].id
}

output "public_subnet_az_map" {
  description = "Map of AZ to public subnet ID"
  value       = { for i, s in aws_subnet.public : s.availability_zone => s.id }
}

output "private_app_subnet_az_map" {
  description = "Map of AZ to private app subnet ID"
  value       = { for i, s in aws_subnet.private_app : s.availability_zone => s.id }
}
