#!/usr/bin/env bash
# Punto 1: cambia el valor del secreto sin tocar el codigo Python
set -euo pipefail
export AWS_PROFILE=${AWS_PROFILE:-user_cli}
export AWS_DEFAULT_REGION=us-east-1

NUEVA=$(aws secretsmanager get-random-password --password-length 20 \
  --exclude-punctuation --query RandomPassword --output text)

# put-secret-value crea una version nueva y le pasa la etiqueta AWSCURRENT;
# la anterior queda como AWSPREVIOUS
aws secretsmanager put-secret-value \
  --secret-id de-aws/p1/demo \
  --secret-string "{\"username\":\"usuario_demo_v2\",\"password\":\"$NUEVA\"}" \
  --query '{version:VersionId,etiquetas:VersionStages}'
unset NUEVA

aws secretsmanager list-secret-version-ids --secret-id de-aws/p1/demo \
  --query 'Versions[].{id:VersionId,etapas:VersionStages}' --output table
