#!/bin/bash
# install-system.sh - Script para instalar sistema base de monitoreo

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
TAILSCALE_AUTHKEY=""  # Opcional: clave de autenticación de Tailscale

# Configurar colores para mensajes
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}===========================================================${NC}"
echo -e "${BLUE}  INSTALACIÓN DEL SISTEMA BASE DE MONITOREO${NC}"
echo -e "${BLUE}===========================================================${NC}"
echo ""

# Paso 1: Actualizar sistema e instalar dependencias básicas
echo -e "${GREEN}[1/6] Actualizando sistema e instalando dependencias básicas...${NC}"
apt update && apt upgrade -y
apt install -y git curl wget nano sudo openssh-server htop net-tools jq

# Paso 2: Crear usuario para el kiosko
echo -e "${GREEN}[2/6] Configurando usuario kiosko...${NC}"
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

# Paso 3: Instalar Node.js usando NVM
echo -e "${GREEN}[3/6] Instalando Node.js vía NVM...${NC}"
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

# Paso 4: Instalar Node-RED
echo -e "${GREEN}[4/6] Instalando Node-RED...${NC}"
# Limpiar cualquier instalación anterior
rm -rf /root/.node-red
mkdir -p /home/$KIOSK_USER/.node-red
chown -R $KIOSK_USER:$KIOSK_USER /home/$KIOSK_USER/.node-red
chmod -R 755 /home/$KIOSK_USER/.node-red

# Instalar Node-RED globalmente
su - $KIOSK_USER -c "source ~/.nvm/nvm.sh && npm install -g --unsafe-perm node-red"

# Configurar settings.js básico
cat > /home/$KIOSK_USER/.node-red/settings.js << EOF
module.exports = {
    // Puerto de Node-RED
    uiPort: $NODE_RED_PORT,
    
    // Archivos de flujo
    flowFile: 'flows.json',
    credentialsFile: 'flows_cred.json',
    
    // Otras configuraciones
    adminAuth: null,
    userDir: '/home/$KIOSK_USER/.node-red'
}
EOF
chown $KIOSK_USER:$KIOSK_USER /home/$KIOSK_USER/.node-red/settings.js

# Crear servicio systemd para Node-RED con variables de entorno explícitas
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

# Paso 5: Instalar entorno para kiosko y Tailscale
echo -e "${GREEN}[5/6] Instalando Tailscale y entorno de kiosko...${NC}"
# Instalar Tailscale
curl -fsSL https://tailscale.com/install.sh | sh

# Configurar Tailscale
if [ -n "$TAILSCALE_AUTHKEY" ]; then
    tailscale up --authkey=$TAILSCALE_AUTHKEY --advertise-routes=localhost/$NODE_RED_PORT --shields-up
else
    echo "Tailscale instalado. Ejecuta 'tailscale up' manualmente para autenticarte"
    echo "Para permitir acceso al puerto de Node-RED: tailscale up --authkey=TU-CLAVE-AQUÍ --advertise-routes=localhost/$NODE_RED_PORT --shields-up"
fi

# Instalar entorno para kiosko
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

# Configurar servicio de kiosko
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

# Paso 6: Crear script para la configuración del proyecto
echo -e "${GREEN}[6/6] Creando script para configuración del proyecto...${NC}"
cat > /home/$KIOSK_USER/setup-project.sh << EOF
#!/bin/bash
# setup-project.sh - Script para configurar el proyecto en Node-RED

# Variables
NODERED_REPO="https://github.com/asproit/produccionMinimo.git"

# Configurar colores para mensajes
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "\${BLUE}==========================================================\${NC}"
echo -e "\${BLUE}  CONFIGURACIÓN DEL PROYECTO NODE-RED\${NC}"
echo -e "\${BLUE}==========================================================\${NC}"
echo ""

# Detener Node-RED
sudo systemctl stop nodered.service
echo -e "\${GREEN}1. Node-RED detenido\${NC}"

# Realizar un backup si hay archivos existentes
BACKUP_DIR="\$HOME/node-red-backup-\$(date +%Y%m%d%H%M%S)"
if [ -f "\$HOME/.node-red/flows.json" ]; then
    mkdir -p \$BACKUP_DIR
    cp -r \$HOME/.node-red/* \$BACKUP_DIR/ 2>/dev/null
    echo -e "\${GREEN}2. Backup creado en \$BACKUP_DIR\${NC}"
fi

# Limpiar directorio de Node-RED
rm -rf \$HOME/.node-red/*
echo -e "\${GREEN}3. Directorio de Node-RED limpiado\${NC}"

# Clonar el repositorio
cd \$HOME/.node-red
git clone \$NODERED_REPO .
echo -e "\${GREEN}4. Repositorio clonado\${NC}"

# Instalar dependencias del proyecto
source \$HOME/.nvm/nvm.sh
npm install --unsafe-perm
echo -e "\${GREEN}5. Dependencias del proyecto instaladas\${NC}"

# Instalar módulos de dashboard específicos
npm install --unsafe-perm @flowfuse/node-red-dashboard node-red-dashboard node-red-contrib-influxdb node-red-contrib-modbus
echo -e "\${GREEN}6. Módulos adicionales instalados\${NC}"

# Reiniciar Node-RED
sudo systemctl start nodered.service
echo -e "\${GREEN}7. Node-RED reiniciado\${NC}"

echo -e "\${BLUE}==========================================================\${NC}"
echo -e "\${GREEN}¡CONFIGURACIÓN DEL PROYECTO COMPLETADA!\${NC}"
echo -e "\${BLUE}==========================================================\${NC}"
echo ""
echo "Node-RED está disponible en: http://localhost:1880"
echo "Si el proyecto se cargó correctamente, los flujos deberían estar disponibles."
echo ""
EOF
chmod +x /home/$KIOSK_USER/setup-project.sh
chown $KIOSK_USER:$KIOSK_USER /home/$KIOSK_USER/setup-project.sh

# Activar servicios
systemctl daemon-reload
systemctl enable nodered.service
systemctl enable kiosk.service

echo -e "${BLUE}===========================================================${NC}"
echo -e "${GREEN}¡INSTALACIÓN DEL SISTEMA BASE COMPLETADA!${NC}"
echo -e "${BLUE}===========================================================${NC}"
echo ""
echo "Se ha creado el script setup-project.sh para configurar el proyecto Node-RED"
echo "Ejecuta el siguiente comando para configurar el proyecto:"
echo "sudo -u $KIOSK_USER /home/$KIOSK_USER/setup-project.sh"
echo ""
echo "Usuario kiosko: $KIOSK_USER"
echo "Contraseña: $KIOSK_PASSWORD"
echo ""
echo -e "${BLUE}Información importante:${NC}"
echo "- Para reiniciar: sudo reboot"
echo "- Para apagar: sudo shutdown -h now"
echo ""

read -p "¿Deseas ejecutar ahora el script de configuración del proyecto? (s/n): " configurar
if [ "$configurar" = "s" ] || [ "$configurar" = "S" ]; then
    sudo -u $KIOSK_USER /home/$KIOSK_USER/setup-project.sh
    echo ""
    read -p "¿Deseas reiniciar ahora para aplicar todos los cambios? (s/n): " reiniciar
    if [ "$reiniciar" = "s" ] || [ "$reiniciar" = "S" ]; then
        reboot
    fi
fi
