data "aws_ssm_parameter" "al2023_ami" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

resource "aws_security_group" "jenkins_sg" {
  name        = "blue-green-jenkins-sg"
  description = "Jenkins UI access from an allowed CIDR only"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "Jenkins UI"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = [var.jenkins_allowed_cidr]
  }

  egress {
    description = "Allow outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name      = "blue-green-jenkins-sg"
    Project   = "AWS Blue Green Container Delivery Platform"
    ManagedBy = "Terraform"
  }
}

# Session Manager access so no SSH port needs to be opened.
resource "aws_iam_role_policy_attachment" "jenkins_ssm" {
  role       = aws_iam_role.jenkins.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_instance" "jenkins" {
  ami                         = data.aws_ssm_parameter.al2023_ami.value
  instance_type               = var.jenkins_instance_type
  subnet_id                   = aws_subnet.public_a.id
  vpc_security_group_ids      = [aws_security_group.jenkins_sg.id]
  iam_instance_profile        = aws_iam_instance_profile.jenkins.name
  associate_public_ip_address = true

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  root_block_device {
    volume_size = 30
    volume_type = "gp3"
    encrypted   = true
  }

  user_data = <<-EOF
    #!/bin/bash
    set -euxo pipefail

    dnf install -y git jq docker python3 python3-pip java-21-amazon-corretto-headless fontconfig

    curl -fsSL -o /etc/yum.repos.d/jenkins.repo https://pkg.jenkins.io/redhat-stable/jenkins.repo
    rpm --import https://pkg.jenkins.io/redhat-stable/jenkins.io-2023.key
    dnf install -y jenkins

    cat > /etc/yum.repos.d/trivy.repo <<'REPO'
    [trivy]
    name=Trivy repository
    baseurl=https://get.trivy.dev/rpm/releases/$basearch/
    gpgcheck=0
    enabled=1
    REPO
    dnf install -y trivy

    usermod -aG docker jenkins
    systemctl enable --now docker
    systemctl enable --now jenkins
  EOF

  # Jenkins state lives on the root volume, so a newer AL2023 AMI must not replace the
  # instance. A stopped instance also reports no public IP, which would force replacement.
  lifecycle {
    ignore_changes = [ami, associate_public_ip_address]
  }

  tags = {
    Name      = "blue-green-jenkins"
    Project   = "AWS Blue Green Container Delivery Platform"
    ManagedBy = "Terraform"
  }
}
