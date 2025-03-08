# Detener Node-RED
sudo systemctl stop nodered.service

# Asegurarse que el directorio del proyecto existe y tiene los archivos correctos
sudo ls -la /home/kiosk/.node-red/projects/produccionMinimo

# Configurar el archivo .config/project-registry.json correctamente
sudo mkdir -p /home/kiosk/.node-red/projects/.config
sudo bash -c 'cat > /home/kiosk/.node-red/projects/.config/project-registry.json << EOF
{
    "projects": {
        "produccionMinimo": {
            "credentialSecret": false,
            "default": true
        }
    },
    "activeProject": "produccionMinimo"
}
EOF'

# Crear un archivo .node-red/.config.projects.json para indicar el proyecto activo
sudo bash -c 'cat > /home/kiosk/.node-red/.config.projects.json << EOF
{
    "activeProject": "produccionMinimo"
}
EOF'

# Ajustar permisos
sudo chown -R kiosk:kiosk /home/kiosk/.node-red

# Reiniciar Node-RED
sudo systemctl restart nodered.service
