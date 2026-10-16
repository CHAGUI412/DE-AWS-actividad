#!/usr/bin/env bash
# Punto 6 - agrega 6 registros, vuelve a correr el crawler y verifica
set -euo pipefail
export AWS_PROFILE=${AWS_PROFILE:-user_cli}
export AWS_DEFAULT_REGION=us-east-1
cd "$(dirname "$0")"
source estado_glue.env

# segundo archivo en la misma carpeta: la tabla apunta a la carpeta, no al archivo
aws s3 cp datos/ventas_extra.csv s3://$BUCKET/ventas/ventas_extra.csv

aws glue start-crawler --name de-aws-crawler-ventas
until [ "$(aws glue get-crawler --name de-aws-crawler-ventas --query Crawler.State --output text)" = "READY" ]; do sleep 10; done
aws glue get-crawler-metrics --crawler-name-list de-aws-crawler-ventas \
  --query 'CrawlerMetricsList[0].{creadas:TablesCreated,actualizadas:TablesUpdated,borradas:TablesDeleted}'

echo "--- esquema despues del segundo crawl (debe seguir corregido) ---"
aws glue get-table --database-name de_aws_ventas --name ventas \
  --query 'Table.{columnas:StorageDescriptor.Columns[].[Name,Type],actualizada:UpdateTime}'

python athena_consultas.py
