# ─────────────────────────────────────────
# VPC
# ─────────────────────────────────────────
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "arquisoft-vpc"
  }
}

# ─────────────────────────────────────────
# Internet Gateway
# ─────────────────────────────────────────
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "arquisoft-igw"
  }
}

# ─────────────────────────────────────────
# Data source: Obtener AZs disponibles
# ─────────────────────────────────────────
data "aws_availability_zones" "available" {
  state = "available"
}

# ─────────────────────────────────────────
# PUBLIC SUBNETS (for ALB and EC2)
# ─────────────────────────────────────────

# Public Subnet 1 (AZ-a)
resource "aws_subnet" "public_1" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = {
    Name = "arquisoft-public-subnet-1"
  }
}

# Public Subnet 2 (AZ-b)
resource "aws_subnet" "public_2" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.3.0/24"
  availability_zone       = data.aws_availability_zones.available.names[1]
  map_public_ip_on_launch = true

  tags = {
    Name = "arquisoft-public-subnet-2"
  }
}

# ─────────────────────────────────────────
# PRIVATE SUBNETS (for RDS and Celery)
# ─────────────────────────────────────────

# Private Subnet 1 (AZ-a)
resource "aws_subnet" "private_1" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]

  tags = {
    Name = "arquisoft-private-subnet-1"
  }
}

# Private Subnet 2 (AZ-b)
resource "aws_subnet" "private_2" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.4.0/24"
  availability_zone = data.aws_availability_zones.available.names[1]

  tags = {
    Name = "arquisoft-private-subnet-2"
  }
}

# ─────────────────────────────────────────
# PUBLIC ROUTE TABLE
# ─────────────────────────────────────────
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "arquisoft-public-rt"
  }
}

# Route: Public subnets → Internet Gateway
resource "aws_route" "internet_access" {
  route_table_id         = aws_route_table.public_rt.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.igw.id
}

# Associate public subnets with public route table
resource "aws_route_table_association" "public_assoc_1" {
  subnet_id      = aws_subnet.public_1.id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_route_table_association" "public_assoc_2" {
  subnet_id      = aws_subnet.public_2.id
  route_table_id = aws_route_table.public_rt.id
}

# ─────────────────────────────────────────
# PRIVATE ROUTE TABLE
# ─────────────────────────────────────────
resource "aws_route_table" "private_rt" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "arquisoft-private-rt"
  }
}

# Associate private subnets with private route table (no internet access for now)
resource "aws_route_table_association" "private_assoc_1" {
  subnet_id      = aws_subnet.private_1.id
  route_table_id = aws_route_table.private_rt.id
}

resource "aws_route_table_association" "private_assoc_2" {
  subnet_id      = aws_subnet.private_2.id
  route_table_id = aws_route_table.private_rt.id
}
