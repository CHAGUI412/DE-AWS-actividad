#!/usr/bin/env bash
# Punto 3 - DocumentDB Serverless (0.5 DCU) + EC2 para el tunel SSH
set -euo pipefail
export AWS_PROFILE=${AWS_PROFILE:-user_cli}
export AWS_DEFAULT_REGION=us-east-1
cd "$(dirname "$0")"

MI_IP=$(curl -s https://checkip.amazonaws.com | tr -d '[:space:]' | awk -F. '{print $1"."$2"."$3".0/24"}')  # /24 y no /32: la IP de salida del proveedor cambia entre conexiones
VPC=$(aws ec2 describe-vpcs --filters Name=isDefault,Values=true --query 'Vpcs[0].VpcId' --output text)
SUBNETS=$(aws ec2 describe-subnets --filters Name=vpc-id,Values=$VPC --query 'Subnets[].SubnetId' --output text)
SUBNET1=$(echo $SUBNETS | cut -d' ' -f1)

# llave SSH para la EC2 (queda local, el .pem esta en .gitignore)
aws ec2 create-key-pair --key-name de-aws-docdb --key-type ed25519 \
  --query KeyMaterial --output text > docdb-key.pem
chmod 400 docdb-key.pem

# grupos de seguridad: SSH solo desde mi IP, 27017 solo desde la EC2
SG_EC2=$(aws ec2 create-security-group --group-name de-aws-docdb-bastion \
  --description "SSH desde mi IP" --vpc-id $VPC --query GroupId --output text)
aws ec2 authorize-security-group-ingress --group-id $SG_EC2 --protocol tcp --port 22 --cidr $MI_IP > /dev/null
SG_DB=$(aws ec2 create-security-group --group-name de-aws-docdb \
  --description "DocumentDB solo desde la EC2" --vpc-id $VPC --query GroupId --output text)
aws ec2 authorize-security-group-ingress --group-id $SG_DB --protocol tcp --port 27017 --source-group $SG_EC2 > /dev/null

# EC2 de salto (t3.micro, IP publica para poder hacer SSH)
AMI=$(aws ssm get-parameter --name /aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64 \
  --query Parameter.Value --output text)
EC2=$(aws ec2 run-instances --image-id $AMI --instance-type t3.micro --key-name de-aws-docdb \
  --network-interfaces "DeviceIndex=0,SubnetId=$SUBNET1,Groups=$SG_EC2,AssociatePublicIpAddress=true" \
  --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=de-aws-docdb-bastion}]" \
  --query 'Instances[0].InstanceId' --output text)

# DocumentDB: cluster con la contrasena administrada en Secrets Manager
aws docdb create-db-subnet-group --db-subnet-group-name de-aws-docdb \
  --db-subnet-group-description "punto 3" --subnet-ids $SUBNETS > /dev/null
aws docdb create-db-cluster --db-cluster-identifier de-aws-docdb \
  --engine docdb --engine-version 5.0.0 \
  --master-username docdbadmin --manage-master-user-password \
  --db-subnet-group-name de-aws-docdb --vpc-security-group-ids $SG_DB \
  --serverless-v2-scaling-configuration MinCapacity=0.5,MaxCapacity=1 \
  --backup-retention-period 1 --no-deletion-protection > /dev/null
aws docdb create-db-instance --db-instance-identifier de-aws-docdb-1 \
  --db-cluster-identifier de-aws-docdb --engine docdb \
  --db-instance-class db.serverless > /dev/null

aws ec2 wait instance-running --instance-ids $EC2
IP_EC2=$(aws ec2 describe-instances --instance-ids $EC2 --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)

cat > estado_docdb.env <<EOF
SG_EC2=$SG_EC2
SG_DB=$SG_DB
EC2=$EC2
IP_EC2=$IP_EC2
EOF

echo "esperando DocumentDB (~10 min)..."
aws docdb wait db-instance-available --db-instance-identifier de-aws-docdb-1
ENDPOINT=$(aws docdb describe-db-clusters --db-cluster-identifier de-aws-docdb --query 'DBClusters[0].Endpoint' --output text)
SECRETO=$(aws docdb describe-db-clusters --db-cluster-identifier de-aws-docdb --query 'DBClusters[0].MasterUserSecret.SecretArn' --output text)
echo "ENDPOINT=$ENDPOINT" >> estado_docdb.env
echo "SECRETO=$SECRETO" >> estado_docdb.env
cat estado_docdb.env

# certificado de AWS para TLS
curl -s -o global-bundle.pem https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem

echo
echo "Tunel (dejar abierto en otra terminal):"
echo "ssh -i docdb-key.pem -N -L 27017:$ENDPOINT:27017 ec2-user@$IP_EC2"
