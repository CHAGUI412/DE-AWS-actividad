#!/usr/bin/env bash
# Punto 6 - sube el CSV, crea la base de datos de Glue y el crawler, y lo ejecuta
set -euo pipefail
export AWS_PROFILE=${AWS_PROFILE:-user_cli}
export AWS_DEFAULT_REGION=us-east-1
cd "$(dirname "$0")"

CUENTA=$(aws sts get-caller-identity --query Account --output text)
BUCKET=de-aws-p6-$CUENTA
ROL=de-aws-glue-crawler

aws s3api create-bucket --bucket $BUCKET > /dev/null
aws s3 cp datos/ventas.csv s3://$BUCKET/ventas/ventas.csv

# rol del crawler: politica administrada de Glue + leer solo la carpeta ventas/
sed "s/BUCKET/$BUCKET/g" rol_s3_lectura.json > /tmp/rol_s3_p6.json
aws iam create-role --role-name $ROL --assume-role-policy-document file://rol_confianza.json > /dev/null
aws iam attach-role-policy --role-name $ROL --policy-arn arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole
aws iam put-role-policy --role-name $ROL --policy-name leer-ventas-p6 --policy-document file:///tmp/rol_s3_p6.json
sleep 10  # que IAM propague el rol

aws glue create-database --database-input '{"Name":"de_aws_ventas","Description":"punto 6"}'

# UpdateBehavior=LOG: si vuelvo a correr el crawler no me pisa las correcciones manuales del esquema
aws glue create-crawler --name de-aws-crawler-ventas --role $ROL \
  --database-name de_aws_ventas \
  --targets "{\"S3Targets\":[{\"Path\":\"s3://$BUCKET/ventas/\"}]}" \
  --schema-change-policy UpdateBehavior=LOG,DeleteBehavior=LOG

aws glue start-crawler --name de-aws-crawler-ventas
echo "esperando el crawler..."
until [ "$(aws glue get-crawler --name de-aws-crawler-ventas --query Crawler.State --output text)" = "READY" ]; do sleep 10; done
aws glue get-crawler --name de-aws-crawler-ventas --query 'Crawler.LastCrawl.{estado:Status,mensaje:MessagePrefix}'

echo "BUCKET=$BUCKET" > estado_glue.env
echo "--- esquema inferido ---"
aws glue get-table --database-name de_aws_ventas --name ventas \
  --query 'Table.StorageDescriptor.Columns[].[Name,Type]' --output table
