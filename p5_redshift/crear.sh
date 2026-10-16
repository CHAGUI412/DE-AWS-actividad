#!/usr/bin/env bash
# Punto 5 - bucket, rol de Redshift para S3 y Redshift Serverless de 4 RPU
set -euo pipefail
export AWS_PROFILE=${AWS_PROFILE:-user_cli}
export AWS_DEFAULT_REGION=us-east-1
cd "$(dirname "$0")"

CUENTA=$(aws sts get-caller-identity --query Account --output text)
BUCKET=de-aws-p5-$CUENTA
ROL=de-aws-redshift-s3

aws s3api create-bucket --bucket $BUCKET > /dev/null

# rol que Redshift asume para leer el bucket en el COPY
sed "s/BUCKET/$BUCKET/g" rol_s3_lectura.json > /tmp/rol_s3_p5.json
ROL_ARN=$(aws iam create-role --role-name $ROL \
  --assume-role-policy-document file://rol_confianza.json --query Role.Arn --output text)
aws iam put-role-policy --role-name $ROL --policy-name leer-bucket-p5 \
  --policy-document file:///tmp/rol_s3_p5.json

# namespace: la contrasena del admin la crea y guarda Redshift en Secrets Manager
aws redshift-serverless create-namespace --namespace-name de-aws-ns \
  --admin-username adminrs --manage-admin-password \
  --db-name dev --iam-roles $ROL_ARN --default-iam-role-arn $ROL_ARN > /dev/null

# workgroup: 4 RPU es la capacidad base mas baja; sin acceso publico
aws redshift-serverless create-workgroup --workgroup-name de-aws-wg \
  --namespace-name de-aws-ns --base-capacity 4 --no-publicly-accessible > /dev/null

# limite de gasto: maximo 4 RPU-hora por dia, al pasarlo se desactiva
WG_ARN=$(aws redshift-serverless get-workgroup --workgroup-name de-aws-wg --query workgroup.workgroupArn --output text)
aws redshift-serverless create-usage-limit --resource-arn $WG_ARN \
  --usage-type serverless-compute --amount 4 --period daily --breach-action deactivate > /dev/null

echo "esperando el workgroup..."
until [ "$(aws redshift-serverless get-workgroup --workgroup-name de-aws-wg --query workgroup.status --output text)" = "AVAILABLE" ]; do sleep 15; done

SECRETO=$(aws redshift-serverless get-namespace --namespace-name de-aws-ns --query namespace.adminPasswordSecretArn --output text)
cat > estado_redshift.env <<EOF
BUCKET=$BUCKET
ROL_ARN=$ROL_ARN
SECRETO=$SECRETO
EOF
cat estado_redshift.env
