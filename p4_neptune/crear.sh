#!/usr/bin/env bash
# Punto 4 - Neptune aprovisionado db.t4g.medium con endpoint publico + IAM
set -euo pipefail
export AWS_PROFILE=${AWS_PROFILE:-user_cli}
export AWS_DEFAULT_REGION=us-east-1
cd "$(dirname "$0")"

MI_IP=$(curl -s https://checkip.amazonaws.com | tr -d '[:space:]' | awk -F. '{print $1"."$2"."$3".0/24"}')  # /24 y no /32: la IP de salida del proveedor cambia entre conexiones
VPC=$(aws ec2 describe-vpcs --filters Name=isDefault,Values=true --query 'Vpcs[0].VpcId' --output text)
SUBNETS=$(aws ec2 describe-subnets --filters Name=vpc-id,Values=$VPC --query 'Subnets[].SubnetId' --output text)

# version mas reciente del motor (los endpoints publicos piden 1.4.6 o superior)
VERSION=$(aws neptune describe-db-engine-versions --engine neptune \
  --query 'DBEngineVersions[-1].EngineVersion' --output text)
echo "version del motor: $VERSION"

# solo mi IP puede llegar al puerto 8182
SG=$(aws ec2 create-security-group --group-name de-aws-neptune \
  --description "Neptune 8182 solo desde mi IP" --vpc-id $VPC --query GroupId --output text)
aws ec2 authorize-security-group-ingress --group-id $SG --protocol tcp --port 8182 --cidr $MI_IP > /dev/null

aws neptune create-db-subnet-group --db-subnet-group-name de-aws-neptune \
  --db-subnet-group-description "punto 4" --subnet-ids $SUBNETS > /dev/null

# autenticacion IAM: obligatoria para endpoint publico, y no hay contrasena
aws neptune create-db-cluster --db-cluster-identifier de-aws-neptune \
  --engine neptune --engine-version $VERSION \
  --enable-iam-database-authentication \
  --db-subnet-group-name de-aws-neptune --vpc-security-group-ids $SG \
  --backup-retention-period 1 --no-deletion-protection > /dev/null

aws neptune create-db-instance --db-instance-identifier de-aws-neptune-1 \
  --db-cluster-identifier de-aws-neptune --engine neptune \
  --db-instance-class db.t4g.medium --publicly-accessible > /dev/null

echo "SG=$SG" > estado_neptune.env
echo "esperando Neptune (~10-15 min)..."
aws neptune wait db-instance-available --db-instance-identifier de-aws-neptune-1

ENDPOINT=$(aws neptune describe-db-clusters --db-cluster-identifier de-aws-neptune \
  --query 'DBClusters[0].Endpoint' --output text)
echo "ENDPOINT=$ENDPOINT" >> estado_neptune.env
cat estado_neptune.env

# prueba rapida: la CLI firma la peticion con las llaves de user_cli
aws neptunedata get-engine-status --endpoint-url https://$ENDPOINT:8182
