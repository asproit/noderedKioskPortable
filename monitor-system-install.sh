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
EOF
chown $KIOSK_USER:$KIOSK_USER /home/$KIOSK_USER/.bashrc

# Cargar NVM y instalar Node.js LTS
su - $KIOSK_USER -c "source ~/.nvm/nvm.sh && nvm install --lts && nvm use --lts && nvm alias default node"

# Obtener la versión exacta y rutas de Node.js
NODE_VERSION=$(su - $KIOSK_USER -c "source ~/.nvm/nvm.sh && node -v")
NODE_VERSION_CLEAN=${NODE_VERSION#v}  # Quitar la 'v' inicial
NODE_PATH="/home/$KIOSK_USER/.nvm/versions/node/$NODE_VERSION_CLEAN/bin/node"
echo -e "${BLUE}Node.js instalado: $NODE_PATH (versión $NODE_VERSION)${NC}"

# Paso 4: Instalar Node-RED y configurar como servicio
echo -e "${GREEN}[4/8] Instalando Node-RED...${NC}"
su - $KIOSK_USER -c "source ~/.nvm/nvm.sh && npm install -g --unsafe-perm node-red"
# Obtener la ruta exacta de Node-RED
NODERED_PATH="/home/$KIOSK_USER/.nvm/versions/node/$NODE_VERSION_CLEAN/bin/node-red"
echo -e "${BLUE}Node-RED instalado: $NODERED_PATH${NC}"

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

# Crear servicio systemd para Node-RED con rutas absolutas
cat > /etc/systemd/system/nodered.service << EOF
[Unit]
Description=Node-RED
After=network.target

[Service]
Type=simple
User=$KIOSK_USER
WorkingDirectory=/home/$KIOSK_USER
Environment="PATH=/home/$KIOSK_USER/.nvm/versions/node/$NODE_VERSION_CLEAN/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
Environment="NODE_PATH=/home/$KIOSK_USER/.nvm/versions/node/$NODE_VERSION_CLEAN/lib/node_modules"
ExecStart=$NODE_PATH $NODERED_PATH
Restart=on-failure
RestartSec=10
KillSignal=SIGINT

[Install]
WantedBy=multi-user.target
EOF

# Paso 5: Clonar e instalar el proyecto de Node-RED
echo -e "${GREEN}[5/8] Configurando proyecto Node-RED...${NC}"
# Iniciar temporalmente Node-RED para crear la estructura de directorio
systemctl start nodered.service
sleep 10  # Dar tiempo a Node-RED para inicializar
systemctl stop nodered.service
sleep 5

# Configurar git para el usuario kiosk
su - $KIOSK_USER -c "git config --global user.name 'Kiosk System'"
su - $KIOSK_USER -c "git config --global user.email 'kiosk@example.com'"
su - $KIOSK_USER -c "git config --global init.defaultBranch main"

# Clonar repositorio
mkdir -p /home/$KIOSK_USER/.node-red/projects
su - $KIOSK_USER -c "cd ~/.node-red/projects && git clone $NODERED_REPO produccionMinimo"

# Configurar como proyecto predeterminado
mkdir -p /home/$KIOSK_USER/.node-red/projects/.config
cat > /home/$KIOSK_USER/.node-red/projects/.config/project-registry.json << EOF
{
    "projects": {
        "produccionMinimo": {
            "credentialSecret": false,
            "default": true
        }
    }
}
EOF

# Instalar dependencias del proyecto
echo -e "${GREEN}Instalando dependencias del proyecto...${NC}"
su - $KIOSK_USER -c "source ~/.nvm/nvm.sh && cd ~/.node-red && npm install @flowfuse/node-red-dashboard@1.16.0 node-red-contrib-influxdb@0.7.0 node-red-contrib-modbus@5.31.0 node-red-contrib-stackhero-influxdb-v2@1.0.4 node-red-dashboard@3.6.5 node-red-node-serialport@2.0.2"
chown -R $KIOSK_USER:$KIOSK_USER /home/$KIOSK_USER/.node-red

# Paso 6: Instalar Tailscale
echo -e "${GREEN}[6/8] Instalando Tailscale...${NC}"
curl -fsSL https://tailscale.com/install.sh | sh

# Configurar Tailscale para permitir tráfico al puerto 1880
if [ -n "$TAILSCALE_AUTHKEY" ]; then
    tailscale up --authkey=$TAILSCALE_AUTHKEY --advertise-routes=localhost/$NODE_RED_PORT --shields-up
else
    echo "Tailscale instalado. Ejecuta 'tailscale up' manualmente para autenticarte"
    echo "Para permitir acceso al puerto de Node-RED: tailscale up --authkey=TU-CLAVE-AQUÍ --advertise-routes=localhost/$NODE_RED_PORT --shields-up"
fi

# Paso 7: Instalar entorno para kiosko (X, openbox, chromium)
echo -e "${GREEN}[7/8] Instalando entorno para kiosko...${NC}"
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

# Paso 8: Activar servicios y últimos ajustes
echo -e "${GREEN}[8/8] Activando servicios...${NC}"
systemctl daemon-reload
systemctl enable nodered.service
systemctl enable kiosk.service
systemctl start nodered.service

# Verificar que el servicio Node-RED esté funcionando
NODERED_STATUS=$(systemctl is-active nodered.service)
if [ "$NODERED_STATUS" = "active" ]; then
    echo -e "${GREEN}Servicio Node-RED iniciado correctamente.${NC}"
else
    echo -e "${RED}Advertencia: El servicio Node-RED no pudo iniciarse. Comprobando logs...${NC}"
    journalctl -u nodered.service -n 20
fi

echo -e "${BLUE}===========================================================${NC}"
echo -e "${GREEN}¡INSTALACIÓN COMPLETADA!${NC}"
echo -e "${BLUE}===========================================================${NC}"
echo ""
echo "Node-RED con proyecto 'produccionMinimo' y dependencias instaladas: http://localhost:$NODE_RED_PORT"
echo "Dashboard: $DASHBOARD_URL"
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
echo -e "${BLUE}Rutas importantes:${NC}"
echo "- Node.js: $NODE_PATH"
echo "- Node-RED: $NODERED_PATH"
echo "- Proyectos Node-RED: /home/$KIOSK_USER/.node-red/projects"
echo ""

read -p "¿Deseas reiniciar ahora para aplicar todos los cambios? (s/n): " reiniciar
if [ "$reiniciar" = "s" ] || [ "$reiniciar" = "S" ]; then
    reboot
fi
