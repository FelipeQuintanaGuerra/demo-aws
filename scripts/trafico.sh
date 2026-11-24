#!/usr/bin/env bash
# Genera trafico continuo contra la API. Se usa durante el despliegue canario:
# sin trafico no hay metricas, y sin metricas la alarma no puede disparar el rollback.
#
# Uso: ./scripts/trafico.sh https://xxxx.execute-api.us-east-1.amazonaws.com/Prod/
set -euo pipefail

URL="${1:?Falta la URL de la API (output ApiUrl del stack demo-app)}"

while true; do
  curl -s -w '  [HTTP %{http_code}]\n' "$URL"
  sleep 0.5
done
