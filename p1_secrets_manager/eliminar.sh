#!/usr/bin/env bash
# Punto 1: borra el secreto (sin ventana de recuperacion) y el rol
set -euo pipefail
export AWS_PROFILE=${AWS_PROFILE:-user_cli}
export AWS_DEFAULT_REGION=us-east-1

aws secretsmanager delete-secret --secret-id de-aws/p1/demo --force-delete-without-recovery
aws iam delete-role-policy --role-name de-aws-lector-p1 --policy-name leer-secreto-p1
aws iam delete-role --role-name de-aws-lector-p1

echo "Evidencia (debe salir vacio o error ResourceNotFound):"
aws secretsmanager list-secrets --filters Key=name,Values=de-aws/p1 --query 'SecretList[].Name'
aws iam get-role --role-name de-aws-lector-p1 2>&1 | tail -1 || true
