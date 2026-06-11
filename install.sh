#!/bin/bash

if [ -z "$BASH_VERSION" ]
then
    exec bash "$0" "$@"
fi

set -e

APP_DIR="/opt/sshmon"
SERVICE_FILE="/etc/systemd/system/sshmon.service"

echo "=================================="
echo "       SSHMON INSTALLER"
echo "=================================="
echo

# ============================================================
# ARQUIVOS OBRIGATÓRIOS
# ============================================================

echo "Verificando arquivos obrigatórios..."

for ARQ in sshmon.py requirements.txt hosts.json
do
    if [ ! -f "$ARQ" ]
    then
        echo
        echo "ERRO: Arquivo não encontrado: $ARQ"
        exit 1
    fi
done

echo "OK"
echo

# ============================================================
# PYTHON
# ============================================================

echo "Verificando Python..."

if ! command -v python3 >/dev/null 2>&1
then

    echo "Python3 não encontrado."

    if [ -f /etc/debian_version ]
    then

        echo "Sistema Debian detectado."

        sudo apt update
        sudo apt install -y python3 python3-venv python3-pip

    elif [ -f /etc/redhat-release ]
    then

        echo "Sistema RHEL/Rocky detectado."

        sudo dnf install -y python3 python3-pip

    else

        echo "Distribuição não suportada."
        echo "Instale o Python manualmente."

        exit 1

    fi

fi

echo "Python OK"
echo

# ============================================================
# SMTP
# ============================================================

echo "=================================="
echo " CONFIGURAÇÃO SMTP"
echo "=================================="
echo

read -p "Servidor SMTP: " SMTP_SERVER

read -p "Porta SMTP [587]: " SMTP_PORT
SMTP_PORT=${SMTP_PORT:-587}

echo
echo "Criptografia:"
echo "1 - STARTTLS"
echo "2 - SSL/TLS"
echo

read -p "Escolha [1]: " SMTP_TLS_OPCAO

if [ "$SMTP_TLS_OPCAO" = "2" ]
then
    SMTP_TLS="ssl"
else
    SMTP_TLS="starttls"
fi

echo

while true
do

    read -p "E-mail remetente: " SMTP_USER

    case "$SMTP_USER" in
        *@*) break ;;
    esac

    echo "E-mail inválido. Deve conter @."

done

echo

while true
do

    printf "Senha do e-mail: "

    stty -echo
    read SMTP_PASS
    stty echo

    printf "\n"

    if [ -n "$SMTP_PASS" ]
    then
        break
    fi

    echo "Senha não pode estar vazia."

done

echo

while true
do

    read -p "E-mail destinatário dos alertas: " SMTP_TO

    case "$SMTP_TO" in
        *@*) break ;;
    esac

    echo "E-mail inválido. Deve conter @."

done

echo

cat > .env << EOF
SMTP_SERVER="$SMTP_SERVER"
SMTP_PORT="$SMTP_PORT"
SMTP_TLS="$SMTP_TLS"
SMTP_USER="$SMTP_USER"
SMTP_PASS="$SMTP_PASS"
SMTP_TO="$SMTP_TO"
INTERVALO_VERIFICACAO="5"
FALHAS_PARA_ALERTA="3"
SSH_TIMEOUT="5"
MAX_LOG_SIZE_MB="10"
EOF

chmod 600 .env

echo ".env criado com sucesso."
echo

# ============================================================
# TESTE SMTP
# ============================================================

echo "Testando autenticação SMTP..."

python3 << EOF
import smtplib
import sys

server = "$SMTP_SERVER"
port = int("$SMTP_PORT")
user = "$SMTP_USER"
password = "$SMTP_PASS"
tls = "$SMTP_TLS"

try:

    if tls == "ssl":

        smtp = smtplib.SMTP_SSL(
            server,
            port,
            timeout=20
        )

    else:

        smtp = smtplib.SMTP(
            server,
            port,
            timeout=20
        )

        smtp.ehlo()
        smtp.starttls()
        smtp.ehlo()

    smtp.login(
        user,
        password
    )

    smtp.quit()

    print("SMTP OK")

except Exception as e:

    print("Falha na autenticação SMTP:")
    print(e)

    sys.exit(1)

EOF

echo "SMTP validado com sucesso."
echo

# ============================================================
# USUÁRIO DO SERVIÇO
# ============================================================

echo "Criando usuário sshmon..."

sudo useradd -r -m -s /bin/bash sshmon 2>/dev/null || true

echo "Usuário sshmon OK"
echo

# ============================================================
# DIRETÓRIOS
# ============================================================

echo "Criando diretórios..."

sudo mkdir -p "$APP_DIR"
sudo mkdir -p /var/log/sshmon
sudo mkdir -p /home/sshmon/.ssh

sudo chown -R sshmon:sshmon /home/sshmon/.ssh

sudo chmod 700 /home/sshmon/.ssh

echo "Diretórios criados."
echo

# ============================================================
# CÓPIA DOS ARQUIVOS
# ============================================================

echo "Copiando arquivos..."

sudo cp sshmon.py "$APP_DIR/"
sudo cp requirements.txt "$APP_DIR/"
sudo cp hosts.json "$APP_DIR/"
sudo cp .env "$APP_DIR/"

sudo chmod 600 "$APP_DIR/.env"

sudo chown -R sshmon:sshmon "$APP_DIR"
sudo chown -R sshmon:sshmon /var/log/sshmon

echo "Arquivos copiados."
echo

# ============================================================
# CHAVE SSH
# ============================================================

echo "=================================="
echo " CONFIGURAÇÃO DA CHAVE SSH"
echo "=================================="
echo
echo "Para autenticação por certificado,"
echo "copie sua chave privada para:"
echo
echo "    /home/sshmon/.ssh/id_rsa"
echo
echo "Permissões recomendadas:"
echo
echo "    sudo chown sshmon:sshmon /home/sshmon/.ssh/id_rsa"
echo "    sudo chmod 600 /home/sshmon/.ssh/id_rsa"
echo

read -p "Deseja configurar a chave SSH agora? (s/n): " EDIT_KEY

case "$EDIT_KEY" in
    [Ss])

    echo
    echo "Abra outro terminal e copie sua chave para:"
    echo
    echo "    /home/sshmon/.ssh/id_rsa"
    echo
    echo "Quando terminar pressione ENTER."
    read

    ;;
esac

echo

if [ ! -f /home/sshmon/.ssh/id_rsa ]
then

    echo
    echo "ATENÇÃO:"
    echo
    echo "Nenhuma chave encontrada em:"
    echo "    /home/sshmon/.ssh/id_rsa"
    echo
    echo "Hosts configurados para autenticação"
    echo "por certificado irão falhar até que"
    echo "a chave seja adicionada."
    echo

else

    sudo chown sshmon:sshmon /home/sshmon/.ssh/id_rsa
    sudo chmod 600 /home/sshmon/.ssh/id_rsa

    echo "Chave SSH encontrada."
    echo

fi

# ============================================================
# AMBIENTE VIRTUAL
# ============================================================

echo "Criando ambiente virtual Python..."

sudo -u sshmon python3 -m venv "$APP_DIR/venv"

echo "Atualizando pip..."

sudo -u sshmon "$APP_DIR/venv/bin/pip" install --upgrade pip

echo "Instalando dependências..."

sudo -u sshmon "$APP_DIR/venv/bin/pip" install \
    -r "$APP_DIR/requirements.txt"

echo "Dependências instaladas."
echo

# ============================================================
# SYSTEMD
# ============================================================

echo "Criando serviço systemd..."

sudo tee "$SERVICE_FILE" > /dev/null << EOF
[Unit]
Description=SSHMON
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=sshmon
WorkingDirectory=$APP_DIR
ExecStart=$APP_DIR/venv/bin/python $APP_DIR/sshmon.py

Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
EOF

echo "Serviço criado."
echo

# ============================================================
# HOSTS.JSON
# ============================================================

echo "Deseja editar o hosts.json agora? (s/n)"
read -p "Escolha: " EDIT_HOSTS

case "$EDIT_HOSTS" in
    [Ss])

    sudo nano "$APP_DIR/hosts.json"

    ;;
esac

# ============================================================
# INICIAR SERVIÇO
# ============================================================

echo
echo "Recarregando systemd..."

sudo systemctl daemon-reload

echo "Habilitando serviço..."

sudo systemctl enable sshmon

echo "Iniciando serviço..."

sudo systemctl restart sshmon

sleep 2

# ============================================================
# STATUS
# ============================================================

echo
echo "=================================="
echo " INSTALAÇÃO CONCLUÍDA"
echo "=================================="
echo

echo "Status atual:"
echo

sudo systemctl --no-pager --full status sshmon | head -20

echo
echo "Arquivos importantes:"
echo
echo "Hosts:"
echo "  $APP_DIR/hosts.json"
echo
echo "SMTP:"
echo "  $APP_DIR/.env"
echo
echo "Chave SSH padrão:"
echo "  /home/sshmon/.ssh/id_rsa"
echo
echo "Logs:"
echo "  /var/log/sshmon/successful.log"
echo "  /var/log/sshmon/unsuccessful.log"
echo "  /var/log/sshmon/accessdenied.log"
echo "  /var/log/sshmon/warnings.log"
echo
echo "Comandos úteis:"
echo
echo "Ver status:"
echo "  sudo systemctl status sshmon"
echo
echo "Reiniciar:"
echo "  sudo systemctl restart sshmon"
echo
echo "Acompanhar logs:"
echo "  sudo journalctl -u sshmon -f"
echo
echo "Ver successful.log:"
echo "  tail -f /var/log/sshmon/successful.log"
echo
echo "Ver unsuccessful.log:"
echo "  tail -f /var/log/sshmon/unsuccessful.log"
echo
echo "Ver accessdenied.log:"
echo "  tail -f /var/log/sshmon/accessdenied.log"
echo
echo "Ver warnings.log:"
echo "  tail -f /var/log/sshmon/warnings.log"
echo
