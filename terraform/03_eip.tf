# Elastic IP for Ingress VIP
resource "aws_eip" "ingress_vip" {
    domain = "vpc"
    depends_on  = [aws_internet_gateway.igw]
    tags = merge(
        var.common_tags,
        {
            Name = "eip-k8s-ingress-vip"
            Role = "ingress-vip"
        }
    )
}


resource "aws_iam_policy" "kube_vip_eip_policy" {
  name        = "kube-vip-eip-access"
  description = "Allows kube-vip to manage AWS Elastic IPs"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect   = "Allow",
        Action   = [
          "ec2:DescribeNetworkInterfaces",
          "ec2:DescribeAddresses",
          "ec2:AssociateAddress",
          "ec2:DisassociateAddress"
        ],
        Resource = "*"
      }
    ]
  })

  tags = merge(
    var.common_tags,
    {
      Name = "policy-kube-vip-eip"
      Role = "iam-policy-ingress"
    }
  )
}
 

resource "aws_iam_role" "kube_vip_node_role" {
  name = "kube-vip-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          Service = "ec2.amazonaws.com"
        },
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = merge(
    var.common_tags,
    {
      Name = "role-kube-vip-node"
      Role = "iam-role-k8s-worker-ingress"
    }
  )
}


# Attach policy to the IAM role
resource "aws_iam_role_policy_attachment" "kube_vip_attach_policy" {
  role       = aws_iam_role.kube_vip_node_role.name
  policy_arn = aws_iam_policy.kube_vip_eip_policy.arn
}


resource "aws_iam_instance_profile" "kube_vip_instance_profile" {
  name = "kube-vip-node-instance-profile"
  role = aws_iam_role.kube_vip_node_role.name

  tags = merge(
    var.common_tags,
    {
      Name = "profile-kube-vip"
      Role = "iam-instance-profile-ingress"
    }
  )
}


resource "aws_route53_record" "ingress_vip" {
  zone_id = var.aws_route53_zone_id
  name    = "elastic"
  type    = "A"
  ttl     = 300
  records = [aws_eip.ingress_vip.public_ip]
}


output "kube_vip_elastic_ip" {
  value = aws_eip.ingress_vip.public_ip
}