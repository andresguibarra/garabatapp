#!/bin/bash
# Compila Garabatapp en modo Release y la instala en /Applications.
# Uso: bash scripts/instalar-garabatapp.sh (desde la carpeta del repo)
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Garabatapp"
BUILD_DIR="${HOME}/Library/Caches/garabatapp-build"
DEST="/Applications/${APP_NAME}.app"

cd "${REPO}"
echo "▶ Rama actual: $(git rev-parse --abbrev-ref HEAD)"

echo "▶ Compilando (Release)…"
xcodebuild -project macshot.xcodeproj -scheme macshot -configuration Release \
  -derivedDataPath "${BUILD_DIR}" -allowProvisioningUpdates build -quiet

APP="${BUILD_DIR}/Build/Products/Release/${APP_NAME}.app"
if [ ! -d "${APP}" ]; then
  echo "✗ No encontré ${APP}"; exit 1
fi

echo "▶ Cerrando la versión que esté abierta…"
pkill -x "${APP_NAME}" >/dev/null 2>&1 || true
sleep 1

echo "▶ Instalando en ${DEST}…"
rm -rf "${DEST}"
ditto "${APP}" "${DEST}"
echo "✓ Copiada a ${DEST}"

echo "▶ Abriendo ${APP_NAME}…"
open "${DEST}"
echo "✓ Listo. Si es la primera vez, dale permiso de Grabación de pantalla y volvé a abrirla."
