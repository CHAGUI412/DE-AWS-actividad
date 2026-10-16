#!/usr/bin/env bash
# Punto 5 - elimina workgroup, namespace (sin snapshot final), rol y bucket
set -euo pipefail
export AWS_PROFILE=${AWS_PROFILE:-user_cli}
export AWS_DEFAULT_REGION=us-east-1
cd "$(dirname "$0")"
source estado_redshift.env

aws redshift-serverless delete-workgroup --workgroup-name de-aws-wg > /dev/null
echo "esperando que se borre el workgroup..."
while aws redshift-serverless get-workgroup --workgroup-name de-aws-wg > /dev/null 2>&1; do sleep 15; done

# sin --final-snapshot-name no se guarda snapshot; el secreto administrado se borra con el namespace
aws redshift-serverless delete-namespace --namespace-name de-aws-ns > /dev/null
while aws redshift-serverless get-namespace --namespace-name de-aws-ns > /dev/null 2>&1; do sleep 15; done

aws iam delete-role-policy --role-name de-aws-redshift-s3 --policy-name leer-bucket-p5
aws iam delete-role --role-name de-aws-redshift-s3
aws s3 rb s3://$BUCKET --force

echo "--- evidencia ---"
aws redshift-serverless list-workgroups --query 'workgroups[].workgroupName'
aws redshift-serverless list-namespaces --query 'namespaces[].namespaceName'
aws redshift-serverless list-snapshots --query 'snapshots[].snapshotName'
aws s3 ls | grep de-aws-p5 || echo "sin bucket de-aws-p5"
