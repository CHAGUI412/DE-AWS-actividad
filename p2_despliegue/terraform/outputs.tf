output "bucket" {
  value = aws_s3_bucket.datos.bucket
}

output "ec2_id" {
  value = aws_instance.app.id
}

output "rds_endpoint" {
  value = aws_db_instance.pg.address
}

# solo el ARN, el valor del secreto nunca lo ve terraform
output "rds_secret_arn" {
  value = aws_db_instance.pg.master_user_secret[0].secret_arn
}
