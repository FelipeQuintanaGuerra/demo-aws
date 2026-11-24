#!/usr/bin/env bash
# Borra TODO lo creado por la demo para no dejar recursos cobrando.
#
# Uso: ./scripts/limpiar.sh [stack-app] [stack-pipeline]
#   stack-app       por defecto: demo-app
#   stack-pipeline  por defecto: demo-pipeline
set -euo pipefail

APP_STACK="${1:-demo-app}"
PIPELINE_STACK="${2:-demo-pipeline}"

BUCKET=$(aws cloudformation describe-stacks \
  --stack-name "$PIPELINE_STACK" \
  --query "Stacks[0].Outputs[?OutputKey=='ArtifactBucketName'].OutputValue" \
  --output text)

echo "1/3 Borrando el stack de la aplicacion ($APP_STACK)..."
aws cloudformation delete-stack --stack-name "$APP_STACK"
aws cloudformation wait stack-delete-complete --stack-name "$APP_STACK"

echo "2/3 Vaciando el bucket de artefactos ($BUCKET)..."
aws s3 rm "s3://$BUCKET" --recursive

echo "3/3 Borrando el stack del pipeline ($PIPELINE_STACK)..."
aws cloudformation delete-stack --stack-name "$PIPELINE_STACK"
aws cloudformation wait stack-delete-complete --stack-name "$PIPELINE_STACK"

echo "Listo. Falta borrar a mano la conexion a GitHub:"
echo "  Consola -> Developer Tools -> Settings -> Connections"
