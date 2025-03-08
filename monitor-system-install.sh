#!/bin/bash
# install-monitor-system.sh - Script para instalar sistema de monitoreo minimalista

# Verificar ejecución como root
if [ "$(id -u)" != "0" ]; then
   echo "Este script debe ejecutarse como root" 
   exit 1
fi

# Variables configurables
KIOSK_USER="kiosk"
KIOSK_PASSWORD="monitor123"  # Cambia esto por seguridad
NODE_RED_PORT=1880
INITIAL_URL="http://localhost:$NODE_RED_PORT"
DASHBOARD_URL="http://localhost:$NODE_RED_PORT/dashboard"
TAILSCALE_AUTHKEY=""  # Opcional: clave de autenticación de Tailscale
NODERED_REPO="https://github.com/asproit/produccionMinimo.git"

# Configurar colores para mensajes
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}===========================================================${NC}"
echo -e "${BLUE}  INSTALACIÓN DE SISTEMA DE MONITOREO MINIMALISTA${NC}"
echo -e "${BLUE}===========================================================${NC}"
echo ""

# Paso 1: Actualizar sistema e instalar dependencias básicas
echo -e "${GREEN}[1/8] Actualizando sistema e instalando dependencias básicas...${NC}"
apt update && apt upgrade -y
apt install -y git curl wget nano sudo openssh-server htop net-tools

# Paso 2: Crear usuario para el kiosko
echo -e "${GREEN}[2/8] Configurando usuario kiosko...${NC}"
if ! id "$KIOSK_USER" &>/dev/null; then
    adduser --gecos "" --disabled-password $KIOSK_USER
    echo "$KIOSK_USER:$KIOSK_PASSWORD" | chpasswd
    usermod -aG sudo $KIOSK_USER
    # Configurar para no pedir contraseña con sudo para ciertos comandos
    echo "$KIOSK_USER ALL=(ALL) NOPASSWD: /sbin/shutdown, /sbin/reboot" >> /etc/sudoers.d/kiosk
    chmod 0440 /etc/sudoers.d/kiosk
fi
# Añadir al grupo video para X server
usermod -aG video $KIOSK_USER

# Paso 3: Instalar Node.js usando NVM (más flexible para actualizaciones)
echo -e "${GREEN}[3/8] Instalando Node.js vía NVM...${NC}"
su - $KIOSK_USER -c "curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.3/install.sh | bash"
# Configurar .bashrc para cargar NVM automáticamente
cat >> /home/$KIOSK_USER/.bashrc << EOF

# NVM Configuration
export NVM_DIR="\$HOME/.nvm"
[ -s "\$NVM_DIR/nvm.sh" ] && \. "\$NVM_DIR/nvm.sh"
[ -s "\$NVM_DIR/bash_completion" ] && \. "\$NVM_DIR/bash_completion"

# Asegurar que HOME esté configurado correctamente
export HOME="/home/$KIOSK_USER"
EOF
chown $KIOSK_USER:$KIOSK_USER /home/$KIOSK_USER/.bashrc

# Cargar NVM y instalar Node.js LTS
su - $KIOSK_USER -c "source ~/.nvm/nvm.sh && nvm install --lts && nvm use --lts && nvm alias default node"

# Obtener la versión y ruta exacta de Node.js
NODE_VERSION=$(su - $KIOSK_USER -c "source ~/.nvm/nvm.sh && node -v")
NODE_VERSION_CLEAN=${NODE_VERSION#v}
echo -e "${BLUE}Versión de Node.js instalada: $NODE_VERSION${NC}"

# Paso 4: Preparar entorno Node-RED y clonar repositorio
echo -e "${GREEN}[4/8] Preparando Node-RED y clonando repositorio...${NC}"

# Verificar y eliminar cualquier instalación anterior en ubicaciones incorrectas
rm -rf /root/.node-red
rm -rf /home/$KIOSK_USER/.npm/_npx

# Crear directorio para Node-RED y configurar permisos
mkdir -p /home/$KIOSK_USER/.node-red
rm -rf /home/$KIOSK_USER/.node-red/*
chown -R $KIOSK_USER:$KIOSK_USER /home/$KIOSK_USER/.node-red
chmod -R 755 /home/$KIOSK_USER/.node-red

# Instalar Node-RED como usuario kiosk
su - $KIOSK_USER -c "source ~/.nvm/nvm.sh && npm install -g --unsafe-perm node-red"

# Clonar el repositorio directamente en la carpeta Node-RED
echo -e "${GREEN}Clonando repositorio de Node-RED directamente...${NC}"
su - $KIOSK_USER -c "cd ~/.node-red && git clone $NODERED_REPO ."

# Verificar que el repositorio se clonó correctamente
if [ ! -f "/home/$KIOSK_USER/.node-red/flows.json" ]; then
    echo -e "${RED}Error: No se pudo clonar el repositorio correctamente.${NC}"
    echo -e "${GREEN}Intentando clonar manualmente...${NC}"
    rm -rf /home/$KIOSK_USER/.node-red/*
    git clone $NODERED_REPO /home/$KIOSK_USER/.node-red/
    chown -R $KIOSK_USER:$KIOSK_USER /home/$KIOSK_USER/.node-red
fi

# Instalar dependencias del proyecto
echo -e "${GREEN}Instalando dependencias del proyecto...${NC}"
su - $KIOSK_USER -c "cd ~/.node-red && source ~/.nvm/nvm.sh && npm install --unsafe-perm"

# Instalar módulos de dashboard específicos si son necesarios
echo -e "${GREEN}Asegurando instalación de módulos de dashboard...${NC}"
su - $KIOSK_USER -c "cd ~/.node-red && source ~/.nvm/nvm.sh && npm install --unsafe-perm @flowfuse/node-red-dashboard node-red-dashboard node-red-contrib-influxdb node-red-contrib-modbus"

# Asegurar permisos correctos nuevamente
chown -R $KIOSK_USER:$KIOSK_USER /home/$KIOSK_USER/.node-red
chmod -R 755 /home/$KIOSK_USER/.node-red

# Crear servicio systemd para Node-RED con variables de entorno explícitas
echo -e "${GREEN}Configurando servicio de Node-RED con permisos explícitos...${NC}"
cat > /etc/systemd/system/nodered.service << EOF
[Unit]
Description=Node-RED
After=network.target

[Service]
Type=simple
User=$KIOSK_USER
Group=$KIOSK_USER
WorkingDirectory=/home/$KIOSK_USER/.node-red
Environment="NODE_RED_OPTIONS=--userDir=/home/$KIOSK_USER/.node-red"
Environment="HOME=/home/$KIOSK_USER"
Environment="PATH=/home/$KIOSK_USER/.nvm/versions/node/v$NODE_VERSION_CLEAN/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
Environment="NODE_PATH=/home/$KIOSK_USER/.nvm/versions/node/v$NODE_VERSION_CLEAN/lib/node_modules"
ExecStart=/home/$KIOSK_USER/.nvm/versions/node/v$NODE_VERSION_CLEAN/bin/node-red
Restart=on-failure
RestartSec=10
KillSignal=SIGINT

[Install]
WantedBy=multi-user.target
EOF

# Paso 5: Instalar Tailscale
echo -e "${GREEN}[5/8] Instalando Tailscale...${NC}"
curl -fsSL https://tailscale.com/install.sh | sh

# Configurar Tailscale para permitir tráfico al puerto 1880
if [ -n "$TAILSCALE_AUTHKEY" ]; then
    tailscale up --authkey=$TAILSCALE_AUTHKEY --advertise-routes=localhost/$NODE_RED_PORT --shields-up
else
    echo "Tailscale instalado. Ejecuta 'tailscale up' manualmente para autenticarte"
    echo "Para permitir acceso al puerto de Node-RED: tailscale up --authkey=TU-CLAVE-AQUÍ --advertise-routes=localhost/$NODE_RED_PORT --shields-up"
fi

# Paso 6: Instalar entorno para kiosko (X, openbox, chromium)
echo -e "${GREEN}[6/8] Instalando entorno para kiosko...${NC}"
apt install -y xorg openbox lightdm chromium x11-xserver-utils unclutter

# Configurar LightDM para autologin
cat > /etc/lightdm/lightdm.conf << EOF
[Seat:*]
autologin-user=$KIOSK_USER
autologin-user-timeout=0
user-session=openbox
EOF

# Configurar Openbox para iniciar Chromium en modo kiosko
mkdir -p /home/$KIOSK_USER/.config/openbox
cat > /home/$KIOSK_USER/.config/openbox/autostart << EOF
# Deshabilitar gestión de energía y salvapantallas
xset -dpms
xset s off
xset s noblank

# Ocultar el cursor después de inactividad
unclutter -idle 0.1 -root &

# Esperar un momento para que Node-RED inicie completamente
sleep 30

# Iniciar Chromium en modo kiosko completo
chromium --no-sandbox --kiosk --incognito --disable-infobars --noerrdialogs --disable-translate --no-first-run --fast --fast-start --disable-features=TranslateUI --disk-cache-dir=/dev/null --disable-pinch --overscroll-history-navigation=0 $INITIAL_URL &
EOF
chown -R $KIOSK_USER:$KIOSK_USER /home/$KIOSK_USER/.config

# Configurar servicio de kiosko con enfoque más robusto
cat > /etc/systemd/system/kiosk.service << EOF
[Unit]
Description=Kiosk Mode Service
After=network.target nodered.service
Wants=graphical.target

[Service]
Type=simple
User=$KIOSK_USER
Environment=DISPLAY=:0
Environment=HOME=/home/$KIOSK_USER
ExecStart=/bin/sh -c "startx -- -nocursor"
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# Configuración para evitar salida del modo kiosko
mkdir -p /etc/X11/xorg.conf.d
cat > /etc/X11/xorg.conf.d/99-kiosk.conf << EOF
Section "ServerFlags"
    Option "DontZap" "true"
EndSection
EOF

# Paso 7: Crear archivo de instrucciones
echo -e "${GREEN}[7/8] Creando documentación...${NC}"
mkdir -p /home/$KIOSK_USER/Desktop
cat > /home/$KIOSK_USER/Desktop/README.txt << EOF
SISTEMA DE MONITOREO MINIMALISTA
================================

Información importante:
- Node-RED está accesible en: $INITIAL_URL
- Dashboard (cuando esté configurado): $DASHBOARD_URL

Consejos de uso:
- Si el dashboard no aparece, verifica que Node-RED esté funcionando correctamente
- Para cambiar a la vista de dashboard después de configurarlo:
  Edita: /home/$KIOSK_USER/.config/openbox/autostart
  Cambia $INITIAL_URL por $DASHBOARD_URL en la línea de Chromium

Control del sistema:
- Para reiniciar: sudo reboot
- Para apagar: sudo shutdown -h now

Rutas importantes:
- Node-RED: /home/$KIOSK_USER/.node-red
- Carpeta de configuración: /home/$KIOSK_USER/.config

Si encuentras problemas:
- Verifica logs: sudo journalctl -u nodered.service -n 50
EOF
chown $KIOSK_USER:$KIOSK_USER /home/$KIOSK_USER/Desktop/README.txt

# Paso 8: Activar servicios y realizar verificación final
echo -e "${GREEN}[8/8] Activando servicios y verificando instalación...${NC}"
systemctl daemon-reload
systemctl enable nodered.service
systemctl enable kiosk.service
systemctl start nodered.service

# Verificar que Node-RED esté funcionando
sleep 5
NODERED_STATUS=$(systemctl is-active nodered.service)
if [ "$NODERED_STATUS" = "active" ]; then
    echo -e "${GREEN}Node-RED inició correctamente.${NC}"
else
    echo -e "${RED}Node-RED no pudo iniciar. Verificando permisos...${NC}"
    chown -R $KIOSK_USER:$KIOSK_USER /home/$KIOSK_USER/.node-red
    systemctl restart nodered.service
    sleep 5
    NODERED_STATUS=$(systemctl is-active nodered.service)
    if [ "$NODERED_STATUS" = "active" ]; then
        echo -e "${GREEN}Node-RED ahora está funcionando después de corregir permisos.${NC}"
    else
        echo -e "${RED}Node-RED sigue sin funcionar. Verificando logs:${NC}"
        journalctl -u nodered.service -n 20
    fi
fi

echo -e "${BLUE}===========================================================${NC}"
echo -e "${GREEN}¡INSTALACIÓN COMPLETADA!${NC}"
echo -e "${BLUE}===========================================================${NC}"
echo ""
echo "Node-RED está disponible en: $INITIAL_URL"
echo "Dashboard (cuando esté configurado): $DASHBOARD_URL"
echo "Tailscale instalado para acceso remoto"
echo "Kiosko configurado para arranque automático"
echo ""
echo "Usuario kiosko: $KIOSK_USER"
echo "Contraseña: $KIOSK_PASSWORD"
echo ""

read -p "¿Deseas reiniciar ahora para aplicar todos los cambios? (s/n): " reiniciar
if [ "$reiniciar" = "s" ] || [ "$reiniciar" = "S" ]; then
    reboot
fi
