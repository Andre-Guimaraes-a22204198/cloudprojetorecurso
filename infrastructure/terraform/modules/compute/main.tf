data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
}

# ----- IAM role: lets order-service/product-service reach SQS via the -----
# ----- default AWS SDK credential chain (instance profile), least-priv -----
resource "aws_iam_role" "app" {
  name = "${var.project}-${var.environment}-app-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "app_sqs" {
  name = "${var.project}-${var.environment}-app-sqs-policy"
  role = aws_iam_role.app.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "sqs:SendMessage",
        "sqs:ReceiveMessage",
        "sqs:DeleteMessage",
        "sqs:GetQueueAttributes",
      ]
      Resource = var.queue_arns
    }]
  })
}

resource "aws_iam_instance_profile" "app" {
  name = "${var.project}-${var.environment}-app-profile"
  role = aws_iam_role.app.name
}

resource "aws_instance" "app" {
  count = 3
  ami   = data.aws_ami.amazon_linux.id
  # t3.small (2GB): t3.micro's 1GB was not enough to run all 4 Spring Boot
  # containers via docker-compose without OOM-related instability.
  instance_type = "t3.small"
  subnet_id            = var.public_subnet_ids[0]
  key_name             = var.key_name
  iam_instance_profile = aws_iam_instance_profile.app.name

  vpc_security_group_ids = [var.app_security_group_id]

  tags = {
    Name = "${var.project}-${var.environment}-app-${count.index + 1}"
  }
}