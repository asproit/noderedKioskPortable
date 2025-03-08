#!/bin/bash
# clean-install.sh - Script para eliminar instalaciones anteriores del sistema de monitoreo

# Verificar ejecución como root
if [ "$(id -u)" != "0" ]; then
   echo "Este script debe ejecutarse como root" 
   exit 1
fi

# Configurar colores para mensajes
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}===========================================================${NC}"
echo -e "${RED}  ELIMINACIÓN DE INSTALACIÓN ANTERIOR DEL SISTEMA DE MONITOREO${NC}"
echo -e "${BLUE}===========================================================${NC}"
echo ""

# Detener servicios
echo -e "${GREEN}[1/4] Deteniendo servicios...${NC}"
systemctl stop nodered.service 2>/dev/null
systemctl stop kiosk.service 2>/dev/null
systemctl disable nodered.service 2>/dev/null
systemctl disable kiosk.service 2>/dev/null

# Eliminar archivos de servicios
echo -e "${GREEN}[2/4] Eliminando archivos de servicios...${NC}"
rm -f /etc/systemd/system/nodered.service
rm -f /etc/systemd/system/kiosk.service
systemctl daemon-reload

# Verificar usuario kiosk
echo -e "${GREEN}[3/4] Verificando usuario kiosk...${NC}"
if id "kiosk" &>/dev/null; then
    echo -e "${BLUE}Eliminando archivos de usuario kiosk...${NC}"
    # Eliminar directorios principales
    rm -rf /home/kiosk/.node-red
    rm -rf /home/kiosk/.nvm
    rm -rf /home/kiosk/.config/openbox
    echo -e "${GREEN}Archivos de usuario kiosk eliminados.${NC}"

    read -p "¿Deseas eliminar completamente el usuario kiosk? (s/n): " eliminar_usuario
    if [ "$eliminar_usuario" = "s" ] || [ "$eliminar_usuario" = "S" ]; then
        userdel -r kiosk
        echo -e "${GREEN}Usuario kiosk eliminado completamente.${NC}"
    else
        echo -e "${GREEN}Usuario kiosk conservado.${NC}"
    fi
else
    echo -e "${GREEN}Usuario kiosk no existe.${NC}"
fi

# Limpiar archivos de configuración
echo -e "${GREEN}[4/4] Limpiando archivos de configuración...${NC}"
rm -f /etc/lightdm/lightdm.conf
rm -rf /etc/X11/xorg.conf.d/99-kiosk.conf

echo -e "${BLUE}===========================================================${NC}"
echo -e "${GREEN}¡LIMPIEZA COMPLETADA!${NC}"
echo -e "${BLUE}===========================================================${NC}"
echo ""
echo "Se han eliminado las instalaciones y configuraciones anteriores del sistema de monitoreo."
echo "Ahora puedes ejecutar el script de instalación para configurar el sistema desde cero."
echo ""
