#!/usr/bin/env bash
# Punto 2 - despliegue con AWS CLI. Guarda los ids en estado_cli.env
set -euo pipefail
export AWS_PROFILE=${AWS_PROFILE:-user_cli}
export AWS_DEFAULT_REGION=us-east-1
cd "$(dirname "$0")"
TAGS='Key=proyecto,Value=de-aws Key=metodo,Value=cli'

CUENTA=$(aws sts get-caller-identity --query Account --output text)
VPC=$(aws ec2 describe-vpcs --filters Name=isDefault,Values=true --query 'Vpcs[0].VpcId' --output text)
SUBNETS=$(aws ec2 describe-subnets --filters Name=vpc-id,Values=$VPC --query 'Subnets[].SubnetId' --output text)
SUBNET1=$(echo $SUBNETS | cut -d' ' -f1)

# red
SG_EC2=$(aws ec2 create-security-group --group-name de-aws-cli-ec2 \
  --description "SG EC2 punto 2 cli" --vpc-id $VPC --query GroupId --output text)
SG_RDS=$(aws ec2 create-security-group --group-name de-aws-cli-rds \
  --description "Postgres solo desde la EC2" --vpc-id $VPC --query GroupId --output text)
aws ec2 authorize-security-group-ingress --group-id $SG_RDS \
  --protocol tcp --port 5432 --source-group $SG_EC2 > /dev/null
aws rds create-db-subnet-group --db-subnet-group-name de-aws-cli-subnets \
  --db-subnet-group-description "punto 2 cli" --subnet-ids $SUBNETS > /dev/null

# S3
BUCKET=de-aws-p2-cli-$CUENTA
aws s3api create-bucket --bucket $BUCKET > /dev/null
aws s3api put-public-access-block --bucket $BUCKET --public-access-block-configuration \
  BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

# EC2
AMI=$(aws ssm get-parameter --name /aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64 \
  --query Parameter.Value --output text)
EC2=$(aws ec2 run-instances --image-id $AMI --instance-type t3.micro --count 1 \
  --network-interfaces "DeviceIndex=0,SubnetId=$SUBNET1,Groups=$SG_EC2,AssociatePublicIpAddress=false" \
  --block-device-mappings 'DeviceName=/dev/xvda,Ebs={VolumeSize=8,VolumeType=gp3}' \
  --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=de-aws-cli-ec2},{Key=metodo,Value=cli}]" \
  --query 'Instances[0].InstanceId' --output text)

# RDS con la contrasena administrada por Secrets Manager
aws rds create-db-instance --db-instance-identifier de-aws-cli-rds \
  --engine postgres --db-instance-class db.t4g.micro \
  --allocated-storage 20 --storage-type gp3 --db-name taller \
  --master-username adminpg --manage-master-user-password \
  --db-subnet-group-name de-aws-cli-subnets --vpc-security-group-ids $SG_RDS \
  --no-publicly-accessible --no-multi-az --backup-retention-period 0 \
  --no-deletion-protection --tags $TAGS > /dev/null

cat > estado_cli.env <<EOF
SG_EC2=$SG_EC2
SG_RDS=$SG_RDS
BUCKET=$BUCKET
EC2=$EC2
EOF
cat estado_cli.env

echo "esperando EC2 y RDS..."
aws ec2 wait instance-running --instance-ids $EC2
aws rds wait db-instance-available --db-instance-identifier de-aws-cli-rds
aws rds describe-db-instances --db-instance-identifier de-aws-cli-rds \
  --query 'DBInstances[0].{estado:DBInstanceStatus,endpoint:Endpoint.Address,secreto:MasterUserSecret.SecretArn}' \
  --output table
