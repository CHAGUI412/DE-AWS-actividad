terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
  }
}

# las credenciales salen del perfil user_cli de ~/.aws/credentials,
# nunca se escriben aqui
provider "aws" {
  region  = var.region
  profile = var.perfil
  default_tags {
    tags = { proyecto = "de-aws", metodo = "terraform" }
  }
}

data "aws_caller_identity" "actual" {}

# ---------- red: se usa la VPC por defecto ----------
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

resource "aws_security_group" "ec2" {
  name        = "de-aws-tf-ec2"
  description = "SG de la EC2 del punto 2, sin entradas"
  vpc_id      = data.aws_vpc.default.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "rds" {
  name        = "de-aws-tf-rds"
  description = "Postgres solo desde la EC2"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.ec2.id]
  }
}

resource "aws_db_subnet_group" "rds" {
  name       = "de-aws-tf-subnets"
  subnet_ids = data.aws_subnets.default.ids
}

# ---------- S3 ----------
resource "aws_s3_bucket" "datos" {
  bucket        = "de-aws-p2-tf-${data.aws_caller_identity.actual.account_id}"
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "datos" {
  bucket                  = aws_s3_bucket.datos.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ---------- EC2 ----------
data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

resource "aws_instance" "app" {
  ami                         = data.aws_ssm_parameter.al2023.value
  instance_type               = var.tipo_ec2
  subnet_id                   = data.aws_subnets.default.ids[0]
  vpc_security_group_ids      = [aws_security_group.ec2.id]
  associate_public_ip_address = false # sin IPv4 publica para no pagarla

  root_block_device {
    volume_size = 8
    volume_type = "gp3"
  }

  tags = { Name = "de-aws-tf-ec2" }
}

# ---------- RDS ----------
resource "aws_db_instance" "pg" {
  identifier             = "de-aws-tf-rds"
  engine                 = "postgres"
  instance_class         = var.tipo_rds
  allocated_storage      = 20
  storage_type           = "gp3"
  db_name                = "taller"
  username               = "adminpg"
  db_subnet_group_name   = aws_db_subnet_group.rds.name
  vpc_security_group_ids = [aws_security_group.rds.id]

  # la contrasena la crea y guarda RDS en Secrets Manager,
  # asi nunca pasa por terraform ni queda en el .tfstate
  manage_master_user_password = true

  publicly_accessible     = false
  multi_az                = false
  backup_retention_period = 0
  skip_final_snapshot     = true
  deletion_protection     = false
  apply_immediately       = true
}
