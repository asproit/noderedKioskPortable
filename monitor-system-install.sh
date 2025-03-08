#!/bin/bash
# install-system.sh - Script para instalar sistema base de monitoreo

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
echo -e "${BLUE}  INSTALACIÓN DEL SISTEMA BASE DE MONITOREO${NC}"
echo -e "${BLUE}===========================================================${NC}"
echo ""

# Paso 1: Actualizar sistema e instalar dependencias básicas
echo -e "${GREEN}[1/7] Actualizando sistema e instalando dependencias básicas...${NC}"
apt update && apt upgrade -y
apt install -y git curl wget nano sudo openssh-server htop net-tools jq ufw

# Paso 2: Configurar usuario para el kiosko
echo -e "${GREEN}[2/7] Configurando usuario para el kiosko...${NC}"
# Ya que usaremos tu usuario existente, solo nos aseguramos de que esté en el grupo sudo y video
usermod -aG sudo $KIOSK_USER
usermod -aG video $KIOSK_USER
# Configurar para no pedir contraseña con sudo para ciertos comandos
echo "$KIOSK_USER ALL=(ALL) NOPASSWD: /sbin/shutdown, /sbin/reboot" >> /etc/sudoers.d/$KIOSK_USER
chmod 0440 /etc/sudoers.d/$KIOSK_USER

# Paso 3: Instalar Node.js usando NVM
echo -e "${GREEN}[3/7] Instalando Node.js vía NVM...${NC}"
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
echo -e "${GREEN}[4/7] Instalando Node-RED...${NC}"
# Limpiar cualquier instalación anterior
rm -rf /root/.node-red
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

# Paso 5: Configurar conectividad y entorno
echo -e "${GREEN}[5/7] Configurando conectividad y entorno de red...${NC}"

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
chromium --no-sandbox --kiosk --incognito --disable-infobars --noerrdialogs --disable-translate --no-first-run --fast --fast-start --disable-features=TranslateUI --disk-cache-dir=/dev/null --disable-pinch --overscroll-history-navigation=0 $INITIAL_URL &
EOF
chown -R $KIOSK_USER:$KIOSK_USER /home/$KIOSK_USER/.config

# Configurar atajo de teclado en OpenBox para cambiar entre vistas
cat > /home/$KIOSK_USER/.config/openbox/rc.xml << EOF
<?xml version="1.0" encoding="UTF-8"?>
<openbox_config xmlns="http://openbox.org/3.4/rc" xmlns:xi="http://www.w3.org/2001/XInclude">
  <resistance>
    <strength>10</strength>
    <screen_edge_strength>20</screen_edge_strength>
  </resistance>
  <focus>
    <focusNew>yes</focusNew>
    <followMouse>no</followMouse>
    <focusLast>yes</focusLast>
    <underMouse>no</underMouse>
    <focusDelay>200</focusDelay>
    <raiseOnFocus>no</raiseOnFocus>
  </focus>
  <placement>
    <policy>Smart</policy>
    <center>yes</center>
    <monitor>Primary</monitor>
    <primaryMonitor>1</primaryMonitor>
  </placement>
  <theme>
    <name>Clearlooks</name>
    <titleLayout>NLIMC</titleLayout>
    <keepBorder>yes</keepBorder>
    <animateIconify>yes</animateIconify>
  </theme>
  <desktops>
    <number>1</number>
    <firstdesk>1</firstdesk>
    <names>
      <name>Desktop 1</name>
    </names>
    <popupTime>875</popupTime>
  </desktops>
  <resize>
    <drawContents>yes</drawContents>
    <popupShow>Nonpixel</popupShow>
    <popupPosition>Center</popupPosition>
    <popupFixedPosition>
      <x>10</x>
      <y>10</y>
    </popupFixedPosition>
  </resize>
  <margins>
    <top>0</top>
    <bottom>0</bottom>
    <left>0</left>
    <right>0</right>
  </margins>
  <keyboard>
    <!-- Atajo para cambiar entre vistas (Ctrl+Alt+D) -->
    <keybind key="C-A-d">
      <action name="Execute">
        <command>sudo /home/$KIOSK_USER/toggle-view.sh</command>
      </action>
    </keybind>
    
    <!-- Atajo para cerrar la ventana activa (Alt+F4) -->
    <keybind key="A-F4">
      <action name="Close"/>
    </keybind>
  </keyboard>
  <mouse>
    <dragThreshold>1</dragThreshold>
    <doubleClickTime>500</doubleClickTime>
    <screenEdgeWarpTime>400</screenEdgeWarpTime>
    <screenEdgeWarpMouse>false</screenEdgeWarpMouse>
    <context name="Frame">
      <mousebind button="A-Left" action="Drag">
        <action name="Move"/>
      </mousebind>
      <mousebind button="A-Right" action="Drag">
        <action name="Resize"/>
      </mousebind>
    </context>
    <context name="Titlebar">
      <mousebind button="Left" action="Press">
        <action name="Focus"/>
        <action name="Raise"/>
      </mousebind>
      <mousebind button="Left" action="Click">
        <action name="Focus"/>
        <action name="Raise"/>
      </mousebind>
      <mousebind button="Left" action="DoubleClick">
        <action name="ToggleMaximizeFull"/>
      </mousebind>
    </context>
  </mouse>
</openbox_config>
EOF
chown $KIOSK_USER:$KIOSK_USER /home/$KIOSK_USER/.config/openbox/rc.xml

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

# Paso 6: Crear scripts de utilidades
echo -e "${GREEN}[6/7] Creando scripts de utilidades...${NC}"

# Script para configurar el proyecto
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
npm install --unsafe-perm @flowfuse/node-red-dashboard node-red-dashboard node-red-contrib-influxdb node-red-contrib-modbus node-red-contrib-stackhero-influxdb-v2 node-red-node-serialport
echo -e "\${GREEN}6. Módulos adicionales instalados\${NC}"

# Reiniciar Node-RED
sudo systemctl start nodered.service
echo -e "\${GREEN}7. Node-RED reiniciado\${NC}"

echo -e "\${BLUE}==========================================================\${NC}"
echo -e "\${GREEN}¡CONFIGURACIÓN DEL PROYECTO COMPLETADA!\${NC}"
echo -e "\${BLUE}==========================================================\${NC}"
echo ""
echo "Node-RED está disponible en: http://localhost:1880"
echo "Desde otras máquinas en la red: http://$STATIC_IP:1880"
echo "Si el proyecto se cargó correctamente, los flujos deberían estar disponibles."
echo ""
EOF
chmod +x /home/$KIOSK_USER/setup-project.sh
chown $KIOSK_USER:$KIOSK_USER /home/$KIOSK_USER/setup-project.sh

# Script para cambiar entre vistas
cat > /home/$KIOSK_USER/toggle-view.sh << EOF
#!/bin/bash

# toggle-view.sh - Cambiar entre vista de editor y dashboard

AUTOSTART="/home/$KIOSK_USER/.config/openbox/autostart"
EDITOR_URL="http://localhost:1880"
DASHBOARD_URL="http://localhost:1880/dashboard"

# Determinar qué URL está actualmente configurada
CURRENT_URL=\$(grep "chromium.*http" \$AUTOSTART | sed -E 's/.*chromium .* (http[^ ]+).*/\1/')

# Cambiar a la otra URL
if [ "\$CURRENT_URL" = "\$EDITOR_URL" ]; then
  # Cambiar a dashboard
  sed -i "s|\$EDITOR_URL|\$DASHBOARD_URL|g" \$AUTOSTART
  echo "Cambiado a vista de Dashboard"
else
  # Cambiar a editor
  sed -i "s|\$DASHBOARD_URL|\$EDITOR_URL|g" \$AUTOSTART
  echo "Cambiado a vista de Editor"
fi

# Reiniciar el servicio de kiosko
systemctl restart kiosk.service
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

# Paso 7: Activar servicios
echo -e "${GREEN}[7/7] Activando servicios...${NC}"
systemctl daemon-reload
systemctl enable nodered.service
systemctl enable kiosk.service
systemctl enable networking

echo -e "${BLUE}===========================================================${NC}"
echo -e "${GREEN}¡INSTALACIÓN DEL SISTEMA BASE COMPLETADA!${NC}"
echo -e "${BLUE}===========================================================${NC}"
echo ""
echo "Configuración de red:"
echo "- IP estática: $STATIC_IP"
echo "- Puerto Node-RED: $NODE_RED_PORT"
echo ""
echo "Scripts disponibles:"
echo "- setup-project.sh: Configura el proyecto Node-RED"
echo "- toggle-view.sh: Cambia entre vistas (editor/dashboard)"
echo "- check-modbus.sh: Verifica la conectividad con dispositivos Modbus"
echo ""
echo "Acceso:"
echo "- Local: http://localhost:1880"
echo "- Red: http://$STATIC_IP:1880"
echo "- Atajo para cambiar vistas: Ctrl+Alt+D"
echo ""
echo "Usuario: $KIOSK_USER"
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
