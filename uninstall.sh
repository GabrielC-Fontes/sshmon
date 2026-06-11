#!/bin/bash
echo "===== SSHMON UNINSTALLER ====="
echo "Deseja realmente desinstalar o SSHMON? [y/N]"
read -r CONFIRM
if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
    echo "Desinstalação cancelada."
    exit 0
fi

echo "Parando serviço..."
sudo systemctl stop sshmon || true
echo "Desabilitando serviço..."
sudo systemctl disable sshmon || true

echo "Removendo arquivo de serviço..."
sudo rm -f \
/etc/systemd/system/sshmon.service

sudo systemctl daemon-reload

sudo rm -rf /opt/sshmon

echo "===== DESINSTALAÇÃO CONCLUIDA ====="