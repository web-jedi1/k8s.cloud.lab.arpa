resource "aws_vpc" "cloud_lab_vpc" {
  cidr_block = "10.0.0.0/16"
  enable_dns_support = true
  enable_dns_hostnames = true

  tags = merge(
    var.common_tags,
    {
      Name = "vpc"
      Role = "vpc"
    }
  )
}


resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.cloud_lab_vpc.id

  tags = merge(
    var.common_tags,
    {
      Name = "cloud-lab-igw"
      Role = "internet-gateway"
    }
  )
}


resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.cloud_lab_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = merge(
    var.common_tags,
    {
      Name = "cloud-lab-public-route-table"
      Role = "route-table-public"
    }
  )
}


resource "aws_route_table_association" "management_rt_assoc" {
  subnet_id      = aws_subnet.management.id
  route_table_id = aws_route_table.public_rt.id
}


resource "aws_subnet" "management" {
  vpc_id                  = aws_vpc.cloud_lab_vpc.id
  cidr_block              = "10.0.0.0/24"
  availability_zone       = var.aws_az
  map_public_ip_on_launch = true

  tags = merge(
    var.common_tags,
    {
      Name = "subnet-management"
      Role = "subnet-management"
    }
  )
}


resource "aws_subnet" "k8s" {
  vpc_id                  = aws_vpc.cloud_lab_vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = var.aws_az
  map_public_ip_on_launch = false

  tags = merge(
    var.common_tags,
    {
      Name = "subnet-k8s"
      Role = "subnet-k8s"
    }
  )
}

resource "aws_route53_zone" "k8s_zone" {
  name = "k8s.arpa.local"
  vpc {
    vpc_id = aws_vpc.cloud_lab_vpc.id 
  }
  comment = "Private hosted zone for k8s.lab.local"
}

resource "aws_eip" "nat_eip" {
  vpc = true

  tags = merge(
    var.common_tags,
    {
      Name = "nat-eip"
      Role = "eip-nat"
    }
  )
}

resource "aws_nat_gateway" "nat_gw" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.management.id
  depends_on    = [aws_internet_gateway.igw]

  tags = merge(
    var.common_tags,
    {
      Name = "cloud-lab-nat-gw"
      Role = "nat-gateway"
    }
  )
}

resource "aws_route_table" "private_rt" {
  vpc_id = aws_vpc.cloud_lab_vpc.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_gw.id
  }

  tags = merge(
    var.common_tags,
    {
      Name = "cloud-lab-private-route-table"
      Role = "route-table-private"
    }
  )
}

resource "aws_route_table_association" "k8s_rt_assoc" {
  subnet_id      = aws_subnet.k8s.id
  route_table_id = aws_route_table.private_rt.id
}
