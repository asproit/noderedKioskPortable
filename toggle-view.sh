#!/bin/bash

# toggle-view.sh - Cambiar entre vista de editor y dashboard

AUTOSTART="/home/kiosk/.config/openbox/autostart"
EDITOR_URL="http://localhost:1880"
DASHBOARD_URL="http://localhost:1880/dashboard"

# Determinar qué URL está actualmente configurada
CURRENT_URL=$(grep "chromium.*http" $AUTOSTART | sed -E 's/.*chromium .* (http[^ ]+).*/\1/')

# Cambiar a la otra URL
if [ "$CURRENT_URL" = "$EDITOR_URL" ]; then
  # Cambiar a dashboard
  sed -i "s|$EDITOR_URL|$DASHBOARD_URL|g" $AUTOSTART
  echo "Cambiado a vista de Dashboard"
else
  # Cambiar a editor
  sed -i "s|$DASHBOARD_URL|$EDITOR_URL|g" $AUTOSTART
  echo "Cambiado a vista de Editor"
fi

# Reiniciar el servicio de kiosko
systemctl restart kiosk.service
