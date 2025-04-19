#
### Security Group for Management Subnet
#
resource "aws_security_group" "horizontal-network-traffic-management" {
  name        = "security-group-horizontal-management"
  description = "Rules for horizontal network traffic within management subnet"
  vpc_id      = aws_vpc.cloud_lab_vpc.id

  tags = merge(
    var.common_tags,
    {
      Name = "security-group-horizontal-management"
      Role = "security-group-management"
    }
  )
}


resource "aws_security_group_rule" "allow-inbound-ssh" {
  type              = "ingress"
  security_group_id = aws_security_group.horizontal-network-traffic-management.id
  cidr_blocks       = ["0.0.0.0/0"]
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
}

resource "aws_security_group_rule" "bastion-egress-to-k8s" {
  type                     = "egress"
  security_group_id        = aws_security_group.horizontal-network-traffic-management.id
  cidr_blocks              = [aws_subnet.k8s.cidr_block]
  from_port                = 22
  to_port                  = 22
  protocol                 = "tcp"
}

resource "aws_security_group_rule" "allow-icmp-from-k8s" {
  type              = "ingress"
  security_group_id = aws_security_group.horizontal-network-traffic-management.id
  cidr_blocks       = [aws_subnet.k8s.cidr_block]
  from_port         = -1
  to_port           = -1
  protocol          = "icmp"
}


#
### Security Group for Generic Internal K8s Traffic
#
resource "aws_security_group" "horizontal-network-generic" {
  name        = "security-group-horizontal-generic"
  description = "Allow management-to-k8s internal communication"
  vpc_id      = aws_vpc.cloud_lab_vpc.id

  tags = merge(
    var.common_tags,
    {
      Name = "security-group-horizontal-generic"
      Role = "security-group-k8s-internal"
    }
  )
}


resource "aws_security_group_rule" "allow-inbound-icmp" {
  type              = "ingress"
  security_group_id = aws_security_group.horizontal-network-generic.id
  cidr_blocks       = [aws_subnet.management.cidr_block]
  from_port         = -1
  to_port           = -1
  protocol          = "icmp"
}

resource "aws_security_group_rule" "allow-inbound-any-tcp-from-management" {
  type              = "ingress"
  security_group_id = aws_security_group.horizontal-network-generic.id
  cidr_blocks       = [aws_subnet.management.cidr_block]
  from_port         = 0
  to_port           = 65535
  protocol          = "tcp"
}

resource "aws_security_group_rule" "worker-egress-to-api" {
  type              = "egress"
  security_group_id = aws_security_group.horizontal-network-generic.id
  cidr_blocks       = [aws_subnet.k8s.cidr_block]
  from_port         = 6443
  to_port           = 6443
  protocol          = "tcp"
}



#
### Security Group for Vertical (Internet) Traffic
#
resource "aws_security_group" "vertical-network-web-outbound" {
  name        = "security-group-vertical-traffic"
  description = "Allow outbound HTTP/HTTPS"
  vpc_id      = aws_vpc.cloud_lab_vpc.id

  tags = merge(
    var.common_tags,
    {
      Name = "security-group-vertical-traffic"
      Role = "security-group-egress"
    }
  )
}

resource "aws_security_group_rule" "allow-outbound-http" {
  type              = "egress"
  security_group_id = aws_security_group.vertical-network-web-outbound.id
  cidr_blocks       = ["0.0.0.0/0"]
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
}

resource "aws_security_group_rule" "allow-outbound-https" {
  type              = "egress"
  security_group_id = aws_security_group.vertical-network-web-outbound.id
  cidr_blocks       = ["0.0.0.0/0"]
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
}

#
### SG Allowing K8S api traffic from VPC
#
resource "aws_security_group" "k8s_api" {
  name        = "security-group-k8s-api"
  description = "Allow access to K8s API from inside VPC"
  vpc_id      = aws_vpc.cloud_lab_vpc.id

  tags = merge(
    var.common_tags,
    {
      Name = "security-group-k8s-api"
      Role = "k8s-api"
    }
  )
}

resource "aws_security_group_rule" "allow-k8s-api" {
  security_group_id = aws_security_group.k8s_api.id
  type = "ingress"
  cidr_blocks = [aws_subnet.k8s.cidr_block]
  from_port = 6443
  to_port = 6443
  protocol = "tcp"
}
