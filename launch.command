#!/bin/bash
# Ninja Saga · lanzador local para macOS/Linux
cd "$(dirname "$0")" || exit 1
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
if ! command -v python3 >/dev/null 2>&1; then
  echo "Python 3 no encontrado. Instálalo con: brew install python"
  read -n 1 -s -r -p "Pulsa una tecla para cerrar..."
  exit 1
fi
python3 runtime/launch.py "$@"
echo
echo "Ninja Saga está en marcha. Puedes cerrar esta ventana."
