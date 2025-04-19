resource "aws_key_pair" "ec2_key" {
  key_name   = "ec2_key"
  public_key = file("~/.ssh/terraform_aws.pub")
}

resource "aws_network_interface" "bastion_host" {
  subnet_id       = aws_subnet.management.id
  private_ips     = ["10.0.0.254"]
  security_groups = [
    aws_security_group.horizontal-network-traffic-management.id,
    aws_security_group.vertical-network-web-outbound.id
  ]

  tags = merge(
    var.common_tags,
    {
      Name        = "bastion-primary-network-interface"
      Role        = "bastion"
    }
  )
}

resource "aws_instance" "bastion_host" {
  count         = 1
  ami           = "ami-0056a7c4c0c442db6"
  instance_type = "t4g.micro"
  subnet_id     = aws_subnet.management.id
  associate_public_ip_address = true
  key_name      = aws_key_pair.ec2_key.key_name

  vpc_security_group_ids = [
    aws_security_group.horizontal-network-traffic-management.id,
    aws_security_group.vertical-network-web-outbound.id
  ]

  tags = merge(
    var.common_tags, 
    {
      Name        = "ec2-bastion-host"
      Role        = "bastion"
    }
  )
}

resource "aws_network_interface_attachment" "attach_to_existing_instance" {
  instance_id          = aws_instance.bastion_host[0].id
  network_interface_id = aws_network_interface.bastion_host.id
  device_index         = 1
}

resource "aws_route53_record" "bastion" {
  for_each = toset(var.bastion_fqdn_list) 
  
  zone_id = var.aws_route53_zone_id
  name    = each.value  
  type    = "A"
  ttl     = 300
  records = [aws_instance.bastion_host[0].public_ip]
}
