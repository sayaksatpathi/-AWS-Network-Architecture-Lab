output "public_route_table_id" {
  value = aws_route_table.public.id
}

output "private_app_route_table_id" {
  value = aws_route_table.private_app.id
}

output "private_db_route_table_id" {
  value = aws_route_table.private_db.id
}

output "nat_gateway_id" {
  value = aws_nat_gateway.this.id
}

output "nat_gateway_public_ip" {
  description = "Elastic IP assigned to the NAT Gateway"
  value       = aws_eip.nat.public_ip
}
