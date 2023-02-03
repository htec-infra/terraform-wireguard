resource "random_password" "handler_id" {
  length  = 16
  special = false
}

resource "aws_eip" "vpn" {
  vpc = true

  tags = {
    Name      = local.display_name
    HandlerId = random_password.handler_id.result
  }
}

resource "aws_security_group" "vpn" {
  name_prefix = "vpn-server-entry-point-"
  description = "Allows HTTP/HTTPS and WireGuard VPN traffic"
  vpc_id      = data.aws_subnet.this.vpc_id

  ingress {
    protocol         = "TCP"
    from_port        = 80
    to_port          = 80
    cidr_blocks      = var.ingress_cidr_blocks #tfsec:ignore:aws-vpc-no-public-ingress-sgr
    ipv6_cidr_blocks = var.ingress_ipv6_cidr_blocks #tfsec:ignore:aws-vpc-no-public-ingress-sgr
    description      = "Allow HTTP traffic"
  }

  ingress {
    protocol         = "TCP"
    from_port        = 443
    to_port          = 443
    cidr_blocks      = var.ingress_cidr_blocks #tfsec:ignore:aws-vpc-no-public-ingress-sgr
    ipv6_cidr_blocks = var.ingress_ipv6_cidr_blocks #tfsec:ignore:aws-vpc-no-public-ingress-sgr
    description      = "Allow HTTPS traffic"
  }

  ingress {
    protocol         = "UDP"
    from_port        = var.wireguard_ingress_settings["from_port"]
    to_port          = var.wireguard_ingress_settings["to_port"]
    cidr_blocks      = var.ingress_cidr_blocks #tfsec:ignore:aws-vpc-no-public-ingress-sgr
    ipv6_cidr_blocks = var.ingress_ipv6_cidr_blocks #tfsec:ignore:aws-vpc-no-public-ingress-sgr
    description      = "Wireguard VPN port"
  }

  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = var.egress_cidr_blocks #tfsec:ignore:aws-ec2-no-public-egress-sgr
    description = "Allow outbound connection to everywhere"
  }

  lifecycle {
    create_before_destroy = true
  }
}

data "template_cloudinit_config" "user_data" {
  part {
    filename     = "init.cfg"
    content_type = "text/cloud-config"
    content = templatefile("${path.module}/templates/init.yaml", {
      cluster_name = local.cluster_name
    })
  }
  part {
    filename     = "associate-ip.sh"
    content_type = "text/x-shellscript"
    content = templatefile("${path.module}/templates/associate-eip.sh", {
      ADDR_HANDLER_ID = random_password.handler_id.result
    })
  }
}

resource "aws_launch_template" "vpn" {
  name_prefix   = local.cluster_name
  image_id      = data.aws_ami.vpn.id
  instance_type = var.instance_type

  user_data = data.template_cloudinit_config.user_data.rendered

  iam_instance_profile {
    arn = aws_iam_instance_profile.vpn.arn
  }

  vpc_security_group_ids = concat(var.security_group_id, [aws_security_group.vpn.id])

  monitoring {
    enabled = true
  }

  metadata_options {
    http_endpoint = "enabled"
    http_tokens = "required"
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name        = "WireGuard VPN"
      Namespace   = var.namespace
      CostCenter  = var.cost_center
      Environment = var.environment
    }
  }
}

resource "aws_autoscaling_group" "vpn" {
  name_prefix      = local.cluster_name
  desired_capacity = 1
  max_size         = 1
  min_size         = 1

  launch_template {
    id      = aws_launch_template.vpn.id
    version = "$Latest"
  }

  vpc_zone_identifier = var.subnet_ids
}





