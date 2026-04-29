# VPC module — creates a complete network with public and private subnets.
#
# Layout (2 AZs):
#   Public subnets  → ALB, NAT Gateway, frontend EKS node group
#   Private subnets → backend EKS node group (compressor + worker), RDS MySQL
#
# Subnets are tagged so the AWS Load Balancer Controller can discover them
# when creating ALBs from Kubernetes Ingress objects.

locals {
  # If single_nat_gateway = true, create only one NAT GW (dev cost saving).
  # Otherwise, create one per AZ (prod HA).
  nat_gateway_count = var.single_nat_gateway ? 1 : length(var.azs)
}

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true # required for EKS node DNS resolution

  tags = {
    Name        = "${var.environment}-vpc"
    Environment = var.environment
  }
}

# ─── Public subnets ───────────────────────────────────────────────────────────

resource "aws_subnet" "public" {
  count = length(var.azs)

  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.azs[count.index]
  map_public_ip_on_launch = true # nodes in public subnets get public IPs

  tags = {
    Name        = "${var.environment}-public-${var.azs[count.index]}"
    Environment = var.environment
    # Required tag: tells the LB controller this subnet is for internet-facing ALBs
    "kubernetes.io/role/elb"                    = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }
}

# ─── Private subnets ──────────────────────────────────────────────────────────

resource "aws_subnet" "private" {
  count = length(var.azs)

  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = var.azs[count.index]

  tags = {
    Name        = "${var.environment}-private-${var.azs[count.index]}"
    Environment = var.environment
    # Required tag: tells the LB controller this subnet is for internal ALBs
    "kubernetes.io/role/internal-elb"           = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }
}

# ─── Internet Gateway ─────────────────────────────────────────────────────────

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name        = "${var.environment}-igw"
    Environment = var.environment
  }
}

# ─── Elastic IPs for NAT Gateways ─────────────────────────────────────────────

resource "aws_eip" "nat" {
  count  = local.nat_gateway_count
  domain = "vpc"

  tags = {
    Name        = "${var.environment}-nat-eip-${count.index + 1}"
    Environment = var.environment
  }

  depends_on = [aws_internet_gateway.main]
}

# ─── NAT Gateways (placed in public subnets) ──────────────────────────────────

resource "aws_nat_gateway" "main" {
  count = local.nat_gateway_count

  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags = {
    Name        = "${var.environment}-nat-${count.index + 1}"
    Environment = var.environment
  }

  depends_on = [aws_internet_gateway.main]
}

# ─── Route tables ─────────────────────────────────────────────────────────────

# Public route table — all traffic goes to the IGW
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name        = "${var.environment}-public-rt"
    Environment = var.environment
  }
}

resource "aws_route_table_association" "public" {
  count          = length(var.azs)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Private route tables — outbound internet traffic exits via NAT Gateway.
# With single_nat_gateway=true, all private subnets share one NAT.
# With single_nat_gateway=false, each private subnet uses its AZ-local NAT.
resource "aws_route_table" "private" {
  count  = length(var.azs)
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main[var.single_nat_gateway ? 0 : count.index].id
  }

  tags = {
    Name        = "${var.environment}-private-rt-${var.azs[count.index]}"
    Environment = var.environment
  }
}

resource "aws_route_table_association" "private" {
  count          = length(var.azs)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}
