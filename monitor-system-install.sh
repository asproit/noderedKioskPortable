#!/bin/bash
# monitor-system-install.sh - Script para instalar sistema de monitoreo minimalista

# Verificar ejecución como root
if [ "$(id -u)" != "0" ]; then
   echo "Este script debe ejecutarse como root" 
   exit 1
fi

# Variables configurables
KIOSK_USER="kiosk"
KIOSK_PASSWORD="monitor123"  # Cambia esto por seguridad
NODE_RED_PORT=1880
DASHBOARD_URL="http://localhost:$NODE_RED_PORT/dashboard"
TAILSCALE_AUTHKEY=""  # Opcional: clave de autenticación de Tailscale

# Configurar colores para mensajes
GREEN='\033[0;32m'
BLUE='\033[0;34m'
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

# Paso 3: Instalar Node.js usando NVM (más flexible para actualizaciones)
echo -e "${GREEN}[3/8] Instalando Node.js vía NVM...${NC}"
su - $KIOSK_USER -c "curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.3/install.sh | bash"
# Cargar NVM y instalar Node.js LTS
su - $KIOSK_USER -c "source ~/.nvm/nvm.sh && nvm install --lts && nvm use --lts"

# Paso 4: Instalar Node-RED y configurar como servicio
echo -e "${GREEN}[4/8] Instalando Node-RED...${NC}"
su - $KIOSK_USER -c "source ~/.nvm/nvm.sh && npm install -g --unsafe-perm node-red"
# Habilitar projects en Node-RED
mkdir -p /home/$KIOSK_USER/.node-red
cat > /home/$KIOSK_USER/.node-red/settings.js << EOF
module.exports = {
    editorTheme: {
        projects: {
            enabled: true
        }
    },
    // Resto de configuración estándar
    uiPort: $NODE_RED_PORT,
    adminAuth: null,
    // Opciones de seguridad adicionales si las necesitas
}
EOF
chown -R $KIOSK_USER:$KIOSK_USER /home/$KIOSK_USER/.node-red

# Crear servicio systemd para Node-RED
cat > /etc/systemd/system/nodered.service << EOF
[Unit]
Description=Node-RED
After=network.target

[Service]
Type=simple
User=$KIOSK_USER
WorkingDirectory=/home/$KIOSK_USER
Environment="PATH=/home/$KIOSK_USER/.nvm/versions/node/\$(ls -t /home/$KIOSK_USER/.nvm/versions/node/ | head -n 1)/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
Environment="NODE_PATH=/home/$KIOSK_USER/.nvm/versions/node/\$(ls -t /home/$KIOSK_USER/.nvm/versions/node/ | head -n 1)/lib/node_modules"
ExecStart=/home/$KIOSK_USER/.nvm/versions/node/\$(ls -t /home/$KIOSK_USER/.nvm/versions/node/ | head -n 1)/bin/node-red
Restart=on-failure
KillSignal=SIGINT

[Install]
WantedBy=multi-user.target
EOF

# Paso 5: Instalar Tailscale
echo -e "${GREEN}[5/8] Instalando Tailscale...${NC}"
curl -fsSL https://tailscale.com/install.sh | sh

# Configurar Tailscale para permitir tráfico al puerto 1880
if [ -n "$TAILSCALE_AUTHKEY" ]; then
    tailscale up --authkey=$TAILSCALE_AUTHKEY --advertise-routes=localhost/$NODE_RED_PORT
else
    echo "Tailscale instalado. Ejecuta 'tailscale up' manualmente para autenticarte"
    echo "Para permitir acceso al puerto de Node-RED: tailscale up --advertise-exit-node --advertise-routes=localhost/$NODE_RED_PORT"
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
chromium --no-sandbox --kiosk --incognito --disable-infobars --noerrdialogs --disable-translate --no-first-run --fast --fast-start --disable-features=TranslateUI --disk-cache-dir=/dev/null --disable-pinch --overscroll-history-navigation=0 $DASHBOARD_URL &
EOF
chown -R $KIOSK_USER:$KIOSK_USER /home/$KIOSK_USER/.config

# Paso 7: Configurar servicio de kiosko
echo -e "${GREEN}[7/8] Configurando servicio de kiosko...${NC}"
cat > /etc/systemd/system/kiosk.service << EOF
[Unit]
Description=Kiosk Mode Service
After=network.target nodered.service
Wants=graphical.target

[Service]
Type=simple
User=$KIOSK_USER
Environment=DISPLAY=:0
ExecStart=/usr/bin/startx
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# Paso 8: Activar servicios y últimos ajustes
echo -e "${GREEN}[8/8] Activando servicios...${NC}"
systemctl daemon-reload
systemctl enable nodered.service
systemctl enable kiosk.service
systemctl start nodered.service

# Configuración para evitar salida del modo kiosko
mkdir -p /etc/X11/xorg.conf.d
cat > /etc/X11/xorg.conf.d/99-kiosk.conf << EOF
Section "ServerFlags"
    Option "DontZap" "true"
EndSection
EOF

echo -e "${BLUE}===========================================================${NC}"
echo -e "${GREEN}¡INSTALACIÓN COMPLETADA!${NC}"
echo -e "${BLUE}===========================================================${NC}"
echo ""
echo "Node-RED con projects activado: http://localhost:$NODE_RED_PORT"
echo "Tailscale instalado para acceso remoto"
echo "Kiosko configurado para arranque automático"
echo ""
echo "Usuario kiosko: $KIOSK_USER"
echo "Contraseña: $KIOSK_PASSWORD"
echo ""
echo -e "${BLUE}Información importante:${NC}"
echo "- Puedes acceder a Node-RED remotamente vía Tailscale"
echo "- Para reiniciar: sudo reboot"
echo "- Para apagar: sudo shutdown -h now"
echo ""

read -p "¿Deseas reiniciar ahora para aplicar todos los cambios? (s/n): " reiniciar
if [ "$reiniciar" = "s" ] || [ "$reiniciar" = "S" ]; then
    reboot
fi
