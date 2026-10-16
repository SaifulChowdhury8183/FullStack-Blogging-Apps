
output "cluster_id" {
  description = "ID of the EKS cluster"
  value       = aws_eks_cluster.devopsshack.id
}

output "cluster_name" {
  description = "Name of the EKS cluster"
  value       = aws_eks_cluster.devopsshack.name
}

output "node_group_id" {
  description = "ID of the managed node group"
  value       = aws_eks_node_group.devopsshack.id
}

output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.devopsshack_vpc.id
}

output "subnet_ids" {
  description = "IDs of both subnets"
  value       = aws_subnet.devopsshack_subnet[*].id
}
