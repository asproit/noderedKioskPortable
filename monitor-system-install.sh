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
apt install -y git curl wget nano sudo openssh-server htop net-tools

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
EOF
chown $KIOSK_USER:$KIOSK_USER /home/$KIOSK_USER/.bashrc

# Cargar NVM y instalar Node.js LTS
su - $KIOSK_USER -c "source ~/.nvm/nvm.sh && nvm install --lts && nvm use --lts && nvm alias default node"

# Obtener la versión exacta y rutas de Node.js
NODE_VERSION=$(su - $KIOSK_USER -c "source ~/.nvm/nvm.sh && node -v")
echo -e "${BLUE}Versión de Node.js instalada: $NODE_VERSION${NC}"

# Determinar si el directorio tiene el prefijo 'v' o no
if su - $KIOSK_USER -c "test -d ~/.nvm/versions/node/${NODE_VERSION}"; then
    NODE_DIR="/home/$KIOSK_USER/.nvm/versions/node/${NODE_VERSION}"
    echo -e "${GREEN}Directorio de Node.js (con 'v'): $NODE_DIR${NC}"
elif su - $KIOSK_USER -c "test -d ~/.nvm/versions/node/${NODE_VERSION#v}"; then
    NODE_DIR="/home/$KIOSK_USER/.nvm/versions/node/${NODE_VERSION#v}"
    echo -e "${GREEN}Directorio de Node.js (sin 'v'): $NODE_DIR${NC}"
else
    echo -e "${RED}No se pudo determinar el directorio de Node.js. Creando enlace simbólico para mayor compatibilidad${NC}"
    # Crear enlace simbólico para ambas variantes
    if su - $KIOSK_USER -c "test -d ~/.nvm/versions/node/${NODE_VERSION}"; then
        mkdir -p /home/$KIOSK_USER/.nvm/versions/node/${NODE_VERSION#v}
        ln -sf /home/$KIOSK_USER/.nvm/versions/node/${NODE_VERSION}/bin /home/$KIOSK_USER/.nvm/versions/node/${NODE_VERSION#v}/bin
        NODE_DIR="/home/$KIOSK_USER/.nvm/versions/node/${NODE_VERSION}"
    elif su - $KIOSK_USER -c "test -d ~/.nvm/versions/node/${NODE_VERSION#v}"; then
        mkdir -p /home/$KIOSK_USER/.nvm/versions/node/${NODE_VERSION}
        ln -sf /home/$KIOSK_USER/.nvm/versions/node/${NODE_VERSION#v}/bin /home/$KIOSK_USER/.nvm/versions/node/${NODE_VERSION}/bin
        NODE_DIR="/home/$KIOSK_USER/.nvm/versions/node/${NODE_VERSION#v}"
    else
        echo -e "${RED}Error crítico: No se pudo encontrar o crear directorios de Node.js${NC}"
        exit 1
    fi
fi

NODE_PATH="$NODE_DIR/bin/node"
echo -e "${BLUE}Node.js ejecutable: $NODE_PATH${NC}"

# Paso 4: Instalar Node-RED
echo -e "${GREEN}[4/6] Instalando Node-RED...${NC}"
su - $KIOSK_USER -c "source ~/.nvm/nvm.sh && npm install -g --unsafe-perm node-red"
NODERED_PATH="$NODE_DIR/bin/node-red"
if [ ! -f "$NODERED_PATH" ]; then
    echo -e "${RED}No se encontró el ejecutable de Node-RED en la ubicación esperada.${NC}"
    NODERED_PATH=$(su - $KIOSK_USER -c "source ~/.nvm/nvm.sh && which node-red")
    echo -e "${GREEN}Usando ruta alternativa de Node-RED: $NODERED_PATH${NC}"
fi

# Crear carpeta .node-red inicial
mkdir -p /home/$KIOSK_USER/.node-red
chown -R $KIOSK_USER:$KIOSK_USER /home/$KIOSK_USER/.node-red

# Crear servicio systemd para Node-RED con rutas absolutas verificadas
cat > /etc/systemd/system/nodered.service << EOF
[Unit]
Description=Node-RED
After=network.target

[Service]
Type=simple
User=$KIOSK_USER
WorkingDirectory=/home/$KIOSK_USER/.node-red
Environment="PATH=$NODE_DIR/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
Environment="NODE_PATH=$NODE_DIR/lib/node_modules"
ExecStart=$NODE_PATH $NODERED_PATH
Restart=on-failure
RestartSec=10
KillSignal=SIGINT

[Install]
WantedBy=multi-user.target
EOF

# Paso 5: Instalar Tailscale y configurar entorno
echo -e "${GREEN}[5/6] Instalando Tailscale...${NC}"
curl -fsSL https://tailscale.com/install.sh | sh

# Configurar Tailscale para permitir tráfico al puerto 1880
if [ -n "$TAILSCALE_AUTHKEY" ]; then
    tailscale up --authkey=$TAILSCALE_AUTHKEY --advertise-routes=localhost/$NODE_RED_PORT --shields-up
else
    echo "Tailscale instalado. Ejecuta 'tailscale up' manualmente para autenticarte"
    echo "Para permitir acceso al puerto de Node-RED: tailscale up --authkey=TU-CLAVE-AQUÍ --advertise-routes=localhost/$NODE_RED_PORT --shields-up"
fi

# Instalar entorno para kiosko
echo -e "${GREEN}Instalando entorno para kiosko...${NC}"
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

# Paso 6: Activar servicios
echo -e "${GREEN}[6/6] Activando servicios...${NC}"
systemctl daemon-reload
systemctl enable nodered.service
systemctl enable kiosk.service

# Crear script para configurar el proyecto
cat > /home/$KIOSK_USER/setup-project.sh << EOF
#!/bin/bash
# Script para configurar el proyecto Node-RED

# Variables
NODERED_REPO="https://github.com/asproit/produccionMinimo.git"
NODE_RED_PORT=1880
DASHBOARD_URL="http://localhost:\$NODE_RED_PORT/dashboard"

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

# Limpiar carpeta .node-red
rm -rf ~/.node-red/*
echo -e "\${GREEN}2. Carpeta .node-red limpiada\${NC}"

# Clonar el repositorio
cd ~/.node-red
git clone \$NODERED_REPO .
echo -e "\${GREEN}3. Repositorio clonado\${NC}"

# Configurar settings.js
cat > ~/.node-red/settings.js << SETTINGSEOF
module.exports = {
    // Puerto de Node-RED
    uiPort: \$NODE_RED_PORT,
    
    // Usar los archivos de flujo del repositorio
    flowFile: 'flows.json',
    credentialsFile: 'flows_cred.json',
    
    // Otras configuraciones opcionales
    adminAuth: null,
    
    // Ruta a la carpeta de nodos de usuario
    userDir: '$HOME/.node-red'
}
SETTINGSEOF
echo -e "\${GREEN}4. Archivo settings.js configurado\${NC}"

# Instalar dependencias
source ~/.nvm/nvm.sh
cd ~/.node-red
npm install --unsafe-perm
echo -e "\${GREEN}5. Dependencias instaladas desde package.json\${NC}"

# Instalar módulos adicionales si son necesarios
npm install --unsafe-perm @flowfuse/node-red-dashboard node-red-dashboard node-red-contrib-influxdb node-red-contrib-modbus
echo -e "\${GREEN}6. Módulos adicionales instalados\${NC}"

# Reiniciar Node-RED
sudo systemctl start nodered.service
echo -e "\${GREEN}7. Node-RED reiniciado\${NC}"

echo -e "\${BLUE}==========================================================\${NC}"
echo -e "\${GREEN}¡CONFIGURACIÓN DE PROYECTO COMPLETADA!\${NC}"
echo -e "\${BLUE}==========================================================\${NC}"
echo ""
echo "Node-RED está disponible en: http://localhost:\$NODE_RED_PORT"
echo "Dashboard (cuando esté configurado): \$DASHBOARD_URL"
echo ""
EOF
chmod +x /home/$KIOSK_USER/setup-project.sh
chown $KIOSK_USER:$KIOSK_USER /home/$KIOSK_USER/setup-project.sh

echo -e "${BLUE}===========================================================${NC}"
echo -e "${GREEN}¡INSTALACIÓN DEL SISTEMA BASE COMPLETADA!${NC}"
echo -e "${BLUE}===========================================================${NC}"
echo ""
echo "Se ha creado el script setup-project.sh para configurar el proyecto Node-RED"
echo "Puedes ejecutarlo con: sudo -u $KIOSK_USER /home/$KIOSK_USER/setup-project.sh"
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
