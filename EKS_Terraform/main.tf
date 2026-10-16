
provider "aws" {
  region = "us-east-2"
}

# STEP 1: Create one VPC for the EKS cluster
resource "aws_vpc" "devopsshack_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "devopsshack-vpc"
  }
}

# STEP 2: Create two public subnets in different Availability Zones
resource "aws_subnet" "devopsshack_subnet" {
  count                   = 2
  vpc_id                  = aws_vpc.devopsshack_vpc.id
  cidr_block              = cidrsubnet(aws_vpc.devopsshack_vpc.cidr_block, 8, count.index)
  availability_zone       = element(["us-east-2a", "us-east-2b"], count.index)
  map_public_ip_on_launch = true

  tags = {
    Name                                  = "devopsshack-subnet-${count.index}"
    "kubernetes.io/cluster/devopsshack-cluster" = "shared"
    "kubernetes.io/role/elb"              = "1"
  }
}

# STEP 3: Create an Internet Gateway
resource "aws_internet_gateway" "devopsshack_igw" {
  vpc_id = aws_vpc.devopsshack_vpc.id

  tags = {
    Name = "devopsshack-igw"
  }
}

# STEP 4: Create a route table with Internet access
resource "aws_route_table" "devopsshack_route_table" {
  vpc_id = aws_vpc.devopsshack_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.devopsshack_igw.id
  }

  tags = {
    Name = "devopsshack-route-table"
  }
}

# STEP 5: Associate both subnets with the route table
resource "aws_route_table_association" "a" {
  count          = 2
  subnet_id      = aws_subnet.devopsshack_subnet[count.index].id
  route_table_id = aws_route_table.devopsshack_route_table.id
}

# STEP 6: Security group for the EKS cluster
resource "aws_security_group" "devopsshack_cluster_sg" {
  name        = "devopsshack-cluster-sg"
  description = "Security group for the EKS cluster"
  vpc_id      = aws_vpc.devopsshack_vpc.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "devopsshack-cluster-sg"
  }
}

# STEP 7: Security group for worker nodes
# No unrestricted inbound rule is configured.
resource "aws_security_group" "devopsshack_node_sg" {
  name        = "devopsshack-node-sg"
  description = "Additional security group for EKS worker nodes"
  vpc_id      = aws_vpc.devopsshack_vpc.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "devopsshack-node-sg"
  }
}

# STEP 8: IAM role for the EKS control plane
resource "aws_iam_role" "devopsshack_cluster_role" {
  name = "devopsshack-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "eks.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "devopsshack_cluster_role_policy" {
  role       = aws_iam_role.devopsshack_cluster_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

# STEP 9: Create ONE EKS cluster
resource "aws_eks_cluster" "devopsshack" {
  name     = "devopsshack-cluster"
  role_arn = aws_iam_role.devopsshack_cluster_role.arn

  vpc_config {
    subnet_ids = aws_subnet.devopsshack_subnet[*].id

    # Attach the cluster security group
    security_group_ids = [
      aws_security_group.devopsshack_cluster_sg.id
    ]

    endpoint_public_access = true
    endpoint_private_access = true
  }

  # Ensure the cluster role policy is attached before cluster creation
  depends_on = [
    aws_iam_role_policy_attachment.devopsshack_cluster_role_policy
  ]
}

# STEP 10: IAM role for EC2 worker nodes
resource "aws_iam_role" "devopsshack_node_group_role" {
  name = "devopsshack-node-group-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

# Allow worker nodes to communicate with EKS
resource "aws_iam_role_policy_attachment" "devopsshack_node_group_role_policy" {
  role       = aws_iam_role.devopsshack_node_group_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

# Allow worker nodes to configure pod networking
resource "aws_iam_role_policy_attachment" "devopsshack_node_group_cni_policy" {
  role       = aws_iam_role.devopsshack_node_group_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

# Allow worker nodes to pull images from ECR
resource "aws_iam_role_policy_attachment" "devopsshack_node_group_registry_policy" {
  role       = aws_iam_role.devopsshack_node_group_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

# STEP 11: Create ONE managed node group with THREE EC2 worker nodes
resource "aws_eks_node_group" "devopsshack" {
  cluster_name    = aws_eks_cluster.devopsshack.name
  node_group_name = "devopsshack-node-group"
  node_role_arn   = aws_iam_role.devopsshack_node_group_role.arn
  subnet_ids      = aws_subnet.devopsshack_subnet[*].id

  scaling_config {
    desired_size = 3
    max_size     = 3
    min_size     = 3
  }

  instance_types = ["t2.large"]

  # Wait for all required node IAM policies before creating the group
  depends_on = [
    aws_iam_role_policy_attachment.devopsshack_node_group_role_policy,
    aws_iam_role_policy_attachment.devopsshack_node_group_cni_policy,
    aws_iam_role_policy_attachment.devopsshack_node_group_registry_policy
  ]
}
