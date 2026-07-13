data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
}

resource "aws_instance" "app" {
  count         = 3
  ami           = data.aws_ami.amazon_linux.id
  instance_type = "t3.micro"
  subnet_id     = var.public_subnet_ids[0]
  key_name      = var.key_name

  vpc_security_group_ids = [var.app_security_group_id]

  tags = {
    Name = "${var.project}-${var.environment}-app-${count.index + 1}"
  }
}