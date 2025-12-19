output "bastion_public_ip" {
  value = aws_instance.bastion.public_ip
}

output "controller_private_ip" {
  value = aws_instance.controller.private_ip
}

output "agent_private_ips" {
  value = [for i in aws_instance.agents : i.private_ip]
}

output "ssh_private_key_path" {
  value = local_file.private_key_pem.filename
}

output "ssh_key_name" {
  value = aws_key_pair.ansible.key_name
}

output "vpc_id" {
  value = aws_vpc.main.id
}

output "public_subnet_id" {
  value = aws_subnet.public.id
}

