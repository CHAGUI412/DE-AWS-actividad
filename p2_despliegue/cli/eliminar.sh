#!/usr/bin/env bash
# Punto 2 - elimina lo creado con crear.sh
set -euo pipefail
export AWS_PROFILE=${AWS_PROFILE:-user_cli}
export AWS_DEFAULT_REGION=us-east-1
cd "$(dirname "$0")"
source estado_cli.env

aws rds delete-db-instance --db-instance-identifier de-aws-cli-rds \
  --skip-final-snapshot --delete-automated-backups > /dev/null
aws ec2 terminate-instances --instance-ids $EC2 > /dev/null
echo "esperando..."
aws ec2 wait instance-terminated --instance-ids $EC2
aws rds wait db-instance-deleted --db-instance-identifier de-aws-cli-rds

aws rds delete-db-subnet-group --db-subnet-group-name de-aws-cli-subnets
aws ec2 delete-security-group --group-id $SG_RDS
aws ec2 delete-security-group --group-id $SG_EC2
aws s3 rb s3://$BUCKET --force

echo "--- evidencia de eliminacion ---"
aws rds describe-db-instances --query "DBInstances[?starts_with(DBInstanceIdentifier,'de-aws')].DBInstanceIdentifier"
aws ec2 describe-instances --filters Name=tag:metodo,Values=cli Name=instance-state-name,Values=pending,running,stopped \
  --query 'Reservations[].Instances[].InstanceId'
aws s3 ls | grep de-aws-p2 || echo "sin buckets de-aws-p2"
aws secretsmanager list-secrets --query "SecretList[?starts_with(Name,'rds!')].Name"
