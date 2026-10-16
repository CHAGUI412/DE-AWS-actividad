#!/usr/bin/env bash
# Punto 1: crea el secreto de prueba y el rol que solo puede leerlo
set -euo pipefail
export AWS_PROFILE=${AWS_PROFILE:-user_cli}
export AWS_DEFAULT_REGION=us-east-1
cd "$(dirname "$0")"

SECRET_NAME="de-aws/p1/demo"
ROLE_NAME="de-aws-lector-p1"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# contraseña ficticia generada por AWS, nunca escrita en el codigo
PASS=$(aws secretsmanager get-random-password --password-length 20 \
  --exclude-punctuation --query RandomPassword --output text)

aws secretsmanager create-secret \
  --name "$SECRET_NAME" \
  --description "Secreto de prueba actividad AWS" \
  --secret-string "{\"username\":\"usuario_demo\",\"password\":\"$PASS\"}" \
  --query ARN --output text
unset PASS

# rol con permiso de leer unicamente ese secreto
sed "s/ACCOUNT_ID/$ACCOUNT_ID/g" confianza_rol.json > /tmp/confianza_p1.json
sed "s/ACCOUNT_ID/$ACCOUNT_ID/g" politica_lectura.json > /tmp/politica_p1.json

aws iam create-role --role-name "$ROLE_NAME" \
  --assume-role-policy-document file:///tmp/confianza_p1.json --query Role.Arn --output text
aws iam put-role-policy --role-name "$ROLE_NAME" \
  --policy-name leer-secreto-p1 --policy-document file:///tmp/politica_p1.json

echo
echo "Listo. Agrega este perfil a ~/.aws/config para que Python use el rol:"
echo
echo "[profile lector-p1]"
echo "role_arn = arn:aws:iam::$ACCOUNT_ID:role/$ROLE_NAME"
echo "source_profile = user_cli"
echo "region = us-east-1"
