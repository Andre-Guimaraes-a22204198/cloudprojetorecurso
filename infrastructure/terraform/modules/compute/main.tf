data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
}

resource "aws_instance" "app" {
  count = 3
  ami   = data.aws_ami.amazon_linux.id
  # t3.small (2GB): t3.micro's 1GB was not enough to run all 4 Spring Boot
  # containers via docker-compose without OOM-related instability.
  instance_type = "t3.small"
  subnet_id     = var.public_subnet_ids[0]
  key_name      = var.key_name

  vpc_security_group_ids = [var.app_security_group_id]

  tags = {
    Name = "${var.project}-${var.environment}-app-${count.index + 1}"
  }
}