#!/bin/bash
# Ninja Saga · detener servidor local (macOS/Linux)
cd "$(dirname "$0")" || exit 1
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
python3 runtime/launch.py --stop
echo
echo "Servidor detenido. Puedes cerrar esta ventana."
