data "aws_availability_zones" "available" {}

# Reuse existing key_pair from 03_bastion.tf

#
# Master node EC2 instances
#
resource "aws_instance" "k8s_master" {
  count         = var.k8s_master_count
  ami           = "ami-0056a7c4c0c442db6"
  instance_type = "t4g.micro"
  subnet_id     = aws_subnet.k8s.id
  key_name      = aws_key_pair.ec2_key.key_name

  vpc_security_group_ids = [
    aws_security_group.horizontal-network-generic.id,
    aws_security_group.k8s_api.id
  ]

  tags = merge(
    var.common_tags,
    {
      Name        = "k8s-master-${count.index + 1}"
      Role        = "k8s-master"
    }
  )

  depends_on = [
    aws_security_group.horizontal-network-generic,
    aws_security_group.k8s_api
  ]
}

#
# Worker node EC2 instances
#
resource "aws_instance" "k8s_workers" {
  count         = var.k8s_worker_count
  ami           = "ami-0056a7c4c0c442db6"
  instance_type = "t4g.micro"
  subnet_id     = aws_subnet.k8s.id
  key_name      = aws_key_pair.ec2_key.key_name
  iam_instance_profile = aws_iam_instance_profile.kube_vip_instance_profile.name

  vpc_security_group_ids = [
    aws_security_group.horizontal-network-generic.id
  ]

  tags = merge( 
    var.common_tags,
    {
      Name        = "k8s-worker-${count.index + 1}"
      Role        = "k8s-worker"
    }
  )

  depends_on = [
    aws_security_group.horizontal-network-generic
  ]
}

resource "aws_route53_record" "k8s_master_record" {
  zone_id = aws_route53_zone.k8s_zone.id
  name    = "api.k8s"
  type    = "A"
  ttl     = 300
  records = [for instance in aws_instance.k8s_master : instance.private_ip]
}

resource "aws_route53_record" "k8s_worker_record" {
  count   = var.k8s_worker_count
  zone_id = aws_route53_zone.k8s_zone.id
  name    = "k8s-worker-${count.index + 1}"
  type    = "A"
  ttl     = 300
  records = [aws_instance.k8s_workers[count.index].private_ip]
}

output "k8s_master_private_ips" {
  description = "Private IPs of all Kubernetes master nodes"
  value       = [for instance in aws_instance.k8s_master : instance.private_ip]
}

output "k8s_worker_private_ips" {
  description = "Private IPs of all Kubernetes worker nodes"
  value       = [for instance in aws_instance.k8s_workers : instance.private_ip]
}
