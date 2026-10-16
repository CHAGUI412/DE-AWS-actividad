#!/usr/bin/env bash
# Punto 6 - elimina crawler, base de datos (y sus tablas), rol y bucket
set -euo pipefail
export AWS_PROFILE=${AWS_PROFILE:-user_cli}
export AWS_DEFAULT_REGION=us-east-1
cd "$(dirname "$0")"
source estado_glue.env

aws glue delete-crawler --name de-aws-crawler-ventas
aws glue delete-database --name de_aws_ventas   # borra tambien ventas y ventas_manual
aws iam detach-role-policy --role-name de-aws-glue-crawler --policy-arn arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole
aws iam delete-role-policy --role-name de-aws-glue-crawler --policy-name leer-ventas-p6
aws iam delete-role --role-name de-aws-glue-crawler
aws s3 rb s3://$BUCKET --force   # datos + resultados de Athena

echo "--- evidencia ---"
aws glue get-databases --query "DatabaseList[?Name=='de_aws_ventas'].Name"
aws glue get-crawler --name de-aws-crawler-ventas 2>&1 | tail -1 || true
aws s3 ls | grep de-aws-p6 || echo "sin bucket de-aws-p6"
