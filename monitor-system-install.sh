#!/bin/bash
# install-complete.sh - Instalación completa del sistema de monitoreo desde cero

# Verificar ejecución como root
if [ "$(id -u)" != "0" ]; then
   echo "Este script debe ejecutarse como root" 
   exit 1
fi

# Variables configurables
KIOSK_USER="pd1"
KIOSK_PASSWORD="aspro1457"  # Tu contraseña normal
NODE_RED_PORT=1880
INITIAL_URL="http://localhost:$NODE_RED_PORT"
TAILSCALE_AUTHKEY=""  # Opcional: clave de autenticación de Tailscale
# Variables para IP estática - MODIFICA ESTAS VARIABLES SEGÚN TU RED
STATIC_IP="192.168.1.136"
NETMASK="255.255.255.0"
GATEWAY="192.168.1.1"
DNS1="8.8.8.8"
DNS2="8.8.4.4"

# Configurar colores para mensajes
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}===========================================================${NC}"
echo -e "${BLUE}  INSTALACIÓN COMPLETA DEL SISTEMA DE MONITOREO${NC}"
echo -e "${BLUE}===========================================================${NC}"
echo ""

# Paso 1: Limpiar cualquier instalación anterior
echo -e "${GREEN}[1/7] Limpiando instalaciones anteriores...${NC}"

# Detener servicios si existen
systemctl stop nodered.service 2>/dev/null
systemctl stop kiosk.service 2>/dev/null
systemctl disable nodered.service 2>/dev/null
systemctl disable kiosk.service 2>/dev/null

# Eliminar archivos de servicios
rm -f /etc/systemd/system/nodered.service
rm -f /etc/systemd/system/kiosk.service
systemctl daemon-reload

# Limpiar archivos de configuración
rm -rf /root/.node-red
rm -rf /home/$KIOSK_USER/.node-red
rm -rf /home/$KIOSK_USER/.npm/_npx
rm -f /etc/lightdm/lightdm.conf
rm -rf /etc/X11/xorg.conf.d/99-kiosk.conf

# Paso 2: Actualizar sistema e instalar dependencias básicas
echo -e "${GREEN}[2/7] Actualizando sistema e instalando dependencias básicas...${NC}"
apt update && apt upgrade -y
apt install -y git curl wget nano sudo openssh-server htop net-tools jq ufw xterm

# Paso 3: Configurar usuario y entorno
echo -e "${GREEN}[3/7] Configurando usuario para el kiosko...${NC}"
# Ya que usaremos tu usuario existente, solo nos aseguramos de que esté en el grupo sudo y video
usermod -aG sudo $KIOSK_USER
usermod -aG video $KIOSK_USER
# Configurar para no pedir contraseña con sudo para ciertos comandos
echo "$KIOSK_USER ALL=(ALL) NOPASSWD: /sbin/shutdown, /sbin/reboot" > /etc/sudoers.d/$KIOSK_USER
chmod 0440 /etc/sudoers.d/$KIOSK_USER

# Paso 4: Instalar Node.js usando NVM
echo -e "${GREEN}[4/7] Instalando Node.js vía NVM...${NC}"
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

# Paso 5: Instalar Node-RED y configurar proyecto
echo -e "${GREEN}[5/7] Instalando Node-RED y configurando proyecto...${NC}"

# Crear carpeta .node-red limpia
mkdir -p /home/$KIOSK_USER/.node-red
chown -R $KIOSK_USER:$KIOSK_USER /home/$KIOSK_USER/.node-red
chmod -R 755 /home/$KIOSK_USER/.node-red

# Instalar Node-RED globalmente
su - $KIOSK_USER -c "source ~/.nvm/nvm.sh && npm install -g --unsafe-perm node-red"

# Configurar settings.js para permitir conexiones externas
cat > /home/$KIOSK_USER/.node-red/settings.js << EOF
module.exports = {
    // Puerto de Node-RED
    uiPort: $NODE_RED_PORT,
    
    // Permitir conexiones desde cualquier IP
    uiHost: "0.0.0.0",
    
    // Archivos de flujo
    flowFile: 'flows.json',
    credentialsFile: 'flows_cred.json',
    
    // Otras configuraciones
    adminAuth: null,
    userDir: '/home/$KIOSK_USER/.node-red'
}
EOF

# Configurar proyecto manualmente con package.json inicial
cat > /home/$KIOSK_USER/.node-red/package.json << EOF
{
    "name": "produccionMinimo",
    "description": "flujo optimizado para utilizarse de forma local de forma ligera para parametros criticos",
    "version": "0.0.1",
    "dependencies": {
        "@flowfuse/node-red-dashboard": "1.16.0",
        "node-red-contrib-influxdb": "0.7.0",
        "node-red-contrib-modbus": "5.31.0",
        "node-red-contrib-stackhero-influxdb-v2": "1.0.4",
        "node-red-dashboard": "3.6.5",
        "node-red-node-serialport": "2.0.2"
    },
    "node-red": {
        "settings": {
            "flowFile": "flows.json",
            "credentialsFile": "flows_cred.json"
        }
    }
}
EOF

# En lugar de clonar directamente, descargamos el repositorio como zip
echo -e "${GREEN}Descargando repositorio del proyecto...${NC}"
cd /tmp
rm -f produccionMinimo.zip
wget -O produccionMinimo.zip https://github.com/asproit/produccionMinimo/archive/refs/heads/main.zip || curl -L -o produccionMinimo.zip https://github.com/asproit/produccionMinimo/archive/refs/heads/main.zip

# Extraer contenido directamente a la carpeta .node-red
echo -e "${GREEN}Extrayendo archivos del proyecto...${NC}"
apt install -y unzip
unzip -o produccionMinimo.zip
cp -f produccionMinimo-main/flows.json /home/$KIOSK_USER/.node-red/
cp -f produccionMinimo-main/flows_cred.json /home/$KIOSK_USER/.node-red/ 2>/dev/null
cp -f produccionMinimo-main/.* /home/$KIOSK_USER/.node-red/ 2>/dev/null
rm -rf produccionMinimo.zip produccionMinimo-main

# Configurar permisos
chown -R $KIOSK_USER:$KIOSK_USER /home/$KIOSK_USER/.node-red

# Instalar dependencias
echo -e "${GREEN}Instalando dependencias del proyecto...${NC}"
su - $KIOSK_USER -c "cd ~/.node-red && source ~/.nvm/nvm.sh && npm install --unsafe-perm"

# Instalar módulos adicionales explícitamente
echo -e "${GREEN}Instalando módulos adicionales...${NC}"
su - $KIOSK_USER -c "cd ~/.node-red && source ~/.nvm/nvm.sh && npm install --unsafe-perm @flowfuse/node-red-dashboard@1.16.0 node-red-dashboard@3.6.5 node-red-contrib-influxdb@0.7.0 node-red-contrib-modbus@5.31.0 node-red-contrib-stackhero-influxdb-v2@1.0.4 node-red-node-serialport@2.0.2"

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

# Paso 6: Configurar conectividad y entorno
echo -e "${GREEN}[6/7] Configurando conectividad y entorno de red...${NC}"

# Configurar IP estática
echo -e "${GREEN}Configurando IP estática $STATIC_IP...${NC}"
# Detectar el nombre de la interfaz de red principal
INTERFACE=$(ip -o link show | awk -F': ' '$2 ~ /^(eth|en|wl)/ {print $2; exit}')
echo "Interfaz de red detectada: $INTERFACE"

# Configurar IP estática usando el nombre de interfaz detectado
cat > /etc/network/interfaces.d/${INTERFACE} << EOF
auto $INTERFACE
iface $INTERFACE inet static
    address $STATIC_IP
    netmask $NETMASK
    gateway $GATEWAY
    dns-nameservers $DNS1 $DNS2
EOF

# Configurar firewall para permitir las conexiones necesarias
echo -e "${GREEN}Configurando firewall...${NC}"
ufw allow 502/tcp  # Puerto Modbus TCP
ufw allow 1880/tcp # Puerto Node-RED
ufw allow ssh      # Mantener acceso SSH
ufw default allow outgoing  # Permitir todas las conexiones salientes
ufw default deny incoming   # Bloquear conexiones entrantes por defecto
echo "y" | ufw enable       # Activar firewall con confirmación automática

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
chromium --no-sandbox --kiosk --incognito --disable-infobars --noerrdialogs --disable-translate --no-first-run --fast --fast-start --disable-features=TranslateUI --disk-cache-dir=/dev/null --disable-pinch --overscroll-history-navigation=0 http://localhost:1880/dashboard &EOF
chown -R $KIOSK_USER:$KIOSK_USER /home/$KIOSK_USER/.config

# Configurar atajo de teclado con xbindkeys para mayor compatibilidad
apt install -y xbindkeys xdotool
cat > /home/$KIOSK_USER/.xbindkeysrc << EOF
# Cambiar entre vistas con Ctrl+Alt+D
"sudo /home/$KIOSK_USER/toggle-view.sh"
    Control+Alt + d
EOF
chown $KIOSK_USER:$KIOSK_USER /home/$KIOSK_USER/.xbindkeysrc

# Actualizar autostart para incluir xbindkeys
sed -i '/unclutter/a # Iniciar xbindkeys para manejar atajos de teclado\nxbindkeys &\n' /home/$KIOSK_USER/.config/openbox/autostart

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

# Paso 7: Crear scripts de utilidades
echo -e "${GREEN}[7/7] Creando scripts de utilidades...${NC}"

# Script para cambiar entre vistas
cat > /home/$KIOSK_USER/toggle-view.sh << EOF
#!/bin/bash

# toggle-view.sh - Cambiar entre vista de editor y dashboard

AUTOSTART="/home/$KIOSK_USER/.config/openbox/autostart"
EDITOR_URL="http://localhost:1880"
DASHBOARD_URL="http://localhost:1880/dashboard"

# Asegurar que estamos ejecutando como root
if [ "\$(id -u)" != "0" ]; then
   echo "Este script debe ejecutarse como root"
   exit 1
fi

# Determinar qué URL está actualmente configurada
CURRENT_URL=\$(grep "chromium.*http" \$AUTOSTART | sed -E 's/.*chromium .* (http[^ ]+).*/\1/')

echo "URL actual: \$CURRENT_URL"

# Cambiar a la otra URL
if [ "\$CURRENT_URL" = "\$EDITOR_URL" ]; then
  # Cambiar a dashboard
  sed -i "s|\$EDITOR_URL|\$DASHBOARD_URL|g" \$AUTOSTART
  echo "Cambiado a vista de Dashboard"
  # Reiniciar chromium directamente
  pkill chromium
  sleep 2
  su - $KIOSK_USER -c "DISPLAY=:0 chromium --no-sandbox --kiosk --incognito --disable-infobars --noerrdialogs --disable-translate --no-first-run --fast --fast-start --disable-features=TranslateUI --disk-cache-dir=/dev/null --disable-pinch --overscroll-history-navigation=0 \$DASHBOARD_URL &"
else
  # Cambiar a editor
  sed -i "s|\$DASHBOARD_URL|\$EDITOR_URL|g" \$AUTOSTART
  echo "Cambiado a vista de Editor"
  # Reiniciar chromium directamente
  pkill chromium
  sleep 2
  su - $KIOSK_USER -c "DISPLAY=:0 chromium --no-sandbox --kiosk --incognito --disable-infobars --noerrdialogs --disable-translate --no-first-run --fast --fast-start --disable-features=TranslateUI --disk-cache-dir=/dev/null --disable-pinch --overscroll-history-navigation=0 \$EDITOR_URL &"
fi
EOF
chmod +x /home/$KIOSK_USER/toggle-view.sh
chown $KIOSK_USER:$KIOSK_USER /home/$KIOSK_USER/toggle-view.sh

# Configurar sudo para el script toggle-view.sh
echo "$KIOSK_USER ALL=(ALL) NOPASSWD: /home/$KIOSK_USER/toggle-view.sh" | sudo tee -a /etc/sudoers.d/$KIOSK_USER

# Crear script para verificar conectividad Modbus
cat > /home/$KIOSK_USER/check-modbus.sh << EOF
#!/bin/bash
# check-modbus.sh - Verificar conectividad Modbus

if [ -z "\$1" ]; then
  echo "Uso: \$0 <ip_address>"
  echo "Ejemplo: \$0 192.168.1.209"
  exit 1
fi

IP=\$1
PORT=502

echo "Verificando conectividad Modbus TCP a \$IP:\$PORT..."
echo "Prueba de ping:"
ping -c 4 \$IP

echo ""
echo "Prueba de conexión al puerto Modbus:"
nc -zv \$IP \$PORT

echo ""
echo "Estado del firewall:"
sudo ufw status | grep 502

echo ""
echo "Si las pruebas fallan, intenta:"
echo "1. Verificar que el dispositivo Modbus esté encendido y conectado a la red"
echo "2. Comprobar que el firewall permite las conexiones (sudo ufw allow 502/tcp)"
echo "3. Asegurarse de que la dirección IP es correcta"
EOF
chmod +x /home/$KIOSK_USER/check-modbus.sh
chown $KIOSK_USER:$KIOSK_USER /home/$KIOSK_USER/check-modbus.sh

# Activar servicios
systemctl daemon-reload
systemctl enable nodered.service
systemctl enable kiosk.service
systemctl enable networking

# Iniciar servicios
systemctl start nodered.service

echo -e "${BLUE}===========================================================${NC}"
echo -e "${GREEN}¡INSTALACIÓN COMPLETA DEL SISTEMA TERMINADA!${NC}"
echo -e "${BLUE}===========================================================${NC}"
echo ""
echo "Configuración de red:"
echo "- IP estática: $STATIC_IP"
echo "- Puerto Node-RED: $NODE_RED_PORT"
echo ""
echo "Accesos:"
echo "- Node-RED local: http://localhost:1880"
echo "- Node-RED en red: http://$STATIC_IP:1880"
echo "- Dashboard: http://localhost:1880/dashboard"
echo ""
echo "Scripts disponibles:"
echo "- toggle-view.sh: Cambia entre vistas (editor/dashboard)"
echo "- check-modbus.sh: Verifica la conectividad con dispositivos Modbus"
echo ""
echo "Atajos de teclado:"
echo "- Ctrl+Alt+D: Cambia entre vistas de editor y dashboard"
echo ""
echo "Usuario: $KIOSK_USER"
echo ""
echo -e "${BLUE}Información importante:${NC}"
echo "- Para reiniciar: sudo reboot"
echo "- Para apagar: sudo shutdown -h now"
echo ""

read -p "¿Deseas reiniciar ahora para aplicar todos los cambios? (s/n): " reiniciar
if [ "$reiniciar" = "s" ] || [ "$reiniciar" = "S" ]; then
    reboot
fi
