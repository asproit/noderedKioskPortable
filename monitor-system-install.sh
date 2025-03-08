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
INITIAL_URL="http://localhost:$NODE_RED_PORT"  # Interfaz principal de Node-RED
DASHBOARD_URL="http://localhost:$NODE_RED_PORT/dashboard"  # Para referencia futura
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
    # Crear enlace simbólico para ambas variantes para aumentar compatibilidad
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

# Paso 4: Instalar Node-RED y configurar como servicio
echo -e "${GREEN}[4/8] Instalando Node-RED...${NC}"
su - $KIOSK_USER -c "source ~/.nvm/nvm.sh && npm install -g --unsafe-perm node-red"
# Verificar instalación de Node-RED
NODERED_PATH="$NODE_DIR/bin/node-red"
if [ ! -f "$NODERED_PATH" ]; then
    echo -e "${RED}No se encontró el ejecutable de Node-RED en la ubicación esperada.${NC}"
    NODERED_PATH=$(su - $KIOSK_USER -c "source ~/.nvm/nvm.sh && which node-red")
    echo -e "${GREEN}Usando ruta alternativa de Node-RED: $NODERED_PATH${NC}"
fi

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

# Crear servicio systemd para Node-RED con rutas absolutas verificadas
cat > /etc/systemd/system/nodered.service << EOF
[Unit]
Description=Node-RED
After=network.target

[Service]
Type=simple
User=$KIOSK_USER
WorkingDirectory=/home/$KIOSK_USER
Environment="PATH=$NODE_DIR/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
Environment="NODE_PATH=$NODE_DIR/lib/node_modules"
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

# Instalar dependencias del proyecto - Asegurar instalación de dashboard
echo -e "${GREEN}Instalando dependencias del proyecto...${NC}"
su - $KIOSK_USER -c "source ~/.nvm/nvm.sh && cd ~/.node-red && npm install --unsafe-perm @flowfuse/node-red-dashboard@1.16.0 node-red-contrib-influxdb@0.7.0 node-red-contrib-modbus@5.31.0 node-red-contrib-stackhero-influxdb-v2@1.0.4 node-red-dashboard@3.6.5 node-red-node-serialport@2.0.2"

# Verificar la instalación de los módulos de dashboard
if su - $KIOSK_USER -c "cd ~/.node-red && npm list | grep -q 'node-red-dashboard'"; then
    echo -e "${GREEN}Módulo dashboard instalado correctamente${NC}"
else
    echo -e "${RED}Error al instalar el módulo dashboard. Reintentando...${NC}"
    su - $KIOSK_USER -c "source ~/.nvm/nvm.sh && cd ~/.node-red && npm install --unsafe-perm node-red-dashboard@3.6.5"
fi

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

# Configurar Openbox para iniciar Chromium en modo kiosko - Usar la interfaz principal inicialmente
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

# Iniciar Chromium en modo kiosko completo - Apuntando a la interfaz principal de Node-RED
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
    echo -e "${RED}Advertencia: El servicio Node-RED no pudo iniciarse. Intentando solucionar...${NC}"
    # Intento de solución automática
    echo -e "${BLUE}Creando enlaces simbólicos para asegurar compatibilidad de rutas...${NC}"
    
    # Crear enlaces simbólicos entre las versiones con y sin 'v'
    if [ -d "/home/$KIOSK_USER/.nvm/versions/node/v${NODE_VERSION#v}" ] && [ ! -d "/home/$KIOSK_USER/.nvm/versions/node/${NODE_VERSION#v}" ]; then
        mkdir -p "/home/$KIOSK_USER/.nvm/versions/node/${NODE_VERSION#v}/bin"
        ln -sf "/home/$KIOSK_USER/.nvm/versions/node/v${NODE_VERSION#v}/bin/node" "/home/$KIOSK_USER/.nvm/versions/node/${NODE_VERSION#v}/bin/node"
        ln -sf "/home/$KIOSK_USER/.nvm/versions/node/v${NODE_VERSION#v}/bin/node-red" "/home/$KIOSK_USER/.nvm/versions/node/${NODE_VERSION#v}/bin/node-red"
        chown -R $KIOSK_USER:$KIOSK_USER "/home/$KIOSK_USER/.nvm/versions/node/${NODE_VERSION#v}"
    elif [ -d "/home/$KIOSK_USER/.nvm/versions/node/${NODE_VERSION#v}" ] && [ ! -d "/home/$KIOSK_USER/.nvm/versions/node/v${NODE_VERSION#v}" ]; then
        mkdir -p "/home/$KIOSK_USER/.nvm/versions/node/v${NODE_VERSION#v}/bin"
        ln -sf "/home/$KIOSK_USER/.nvm/versions/node/${NODE_VERSION#v}/bin/node" "/home/$KIOSK_USER/.nvm/versions/node/v${NODE_VERSION#v}/bin/node"
        ln -sf "/home/$KIOSK_USER/.nvm/versions/node/${NODE_VERSION#v}/bin/node-red" "/home/$KIOSK_USER/.nvm/versions/node/v${NODE_VERSION#v}/bin/node-red"
        chown -R $KIOSK_USER:$KIOSK_USER "/home/$KIOSK_USER/.nvm/versions/node/v${NODE_VERSION#v}"
    fi
    
    systemctl restart nodered.service
    sleep 5
    NODERED_STATUS=$(systemctl is-active nodered.service)
    if [ "$NODERED_STATUS" = "active" ]; then
        echo -e "${GREEN}¡Éxito! El servicio Node-RED ahora está funcionando correctamente.${NC}"
    else
        echo -e "${RED}Problemas persistentes con Node-RED. Por favor, verifica los logs:${NC}"
        journalctl -u nodered.service -n 20
    fi
fi

# Crear un archivo README para instrucciones sobre cómo configurar el dashboard
mkdir -p /home/$KIOSK_USER/Desktop
cat > /home/$KIOSK_USER/Desktop/README.txt << EOF
SISTEMA DE MONITOREO MINIMALISTA
================================

Información importante:
- Node-RED está accesible en: $INITIAL_URL
- Para acceder al dashboard (una vez configurado): $DASHBOARD_URL

Configuración del Dashboard:
1. Accede a Node-RED y configura los flujos con widgets de dashboard
2. Instala nodos adicionales si es necesario
3. Una vez configurado, puedes modificar el archivo autostart para apuntar directamente al dashboard:
   Edita: /home/$KIOSK_USER/.config/openbox/autostart
   Cambia $INITIAL_URL por $DASHBOARD_URL en la línea de Chromium

Reinicio o Apagado:
- Para reiniciar: sudo reboot
- Para apagar: sudo shutdown -h now

Rutas importantes:
- Node.js: $NODE_PATH
- Node-RED: $NODERED_PATH
- Proyectos Node-RED: /home/$KIOSK_USER/.node-red/projects
EOF
chown $KIOSK_USER:$KIOSK_USER /home/$KIOSK_USER/Desktop/README.txt

echo -e "${BLUE}===========================================================${NC}"
echo -e "${GREEN}¡INSTALACIÓN COMPLETADA!${NC}"
echo -e "${BLUE}===========================================================${NC}"
echo ""
echo "Node-RED con proyecto 'produccionMinimo' y dependencias instaladas: $INITIAL_URL"
echo "Dashboard (cuando esté configurado): $DASHBOARD_URL"
echo "Tailscale instalado para acceso remoto"
echo "Kiosko configurado para arranque automático"
echo ""
echo "Usuario kiosko: $KIOSK_USER"
echo "Contraseña: $KIOSK_PASSWORD"
echo ""
echo -e "${BLUE}Información importante:${NC}"
echo "- Accede a Node-RED para configurar el dashboard"
echo "- Puedes acceder a Node-RED remotamente vía Tailscale"
echo "- Se ha creado un archivo README en el escritorio con instrucciones"
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
