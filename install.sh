#!/bin/bash

if [ -z "$BASH_VERSION" ]
then
    exec bash "$0" "$@"
fi

set -e

APP_DIR="/opt/sshmon"
SERVICE_FILE="/etc/systemd/system/sshmon.service"
SECRET_DIR="/etc/sshmon"
SMTP_PASS_ENC_FILE="$SECRET_DIR/smtp_pass.enc"
SMTP_PASS_KEY_FILE="$SECRET_DIR/smtp_pass.key"
SMTP_SECRET_TMP=""

cleanup_secret_tmp()
{
    if [ -n "$SMTP_SECRET_TMP" ] && [ -d "$SMTP_SECRET_TMP" ]
    then
        rm -rf "$SMTP_SECRET_TMP"
    fi
}

trap cleanup_secret_tmp EXIT

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

PYTHON_BIN=""

python_can_create_venv()
{
    TEST_VENV=$(mktemp -d /tmp/sshmon-venv-test.XXXXXX)

    if "$1" -m venv "$TEST_VENV" >/dev/null 2>&1
    then
        rm -rf "$TEST_VENV"
        return 0
    fi

    rm -rf "$TEST_VENV"
    return 1
}

detect_python_venv()
{
    for PYTHON_CANDIDATE in python3 /usr/bin/python3 python3.13 python3.12 python3.11 python3.10 python3.9
    do
        if command -v "$PYTHON_CANDIDATE" >/dev/null 2>&1
        then
            PYTHON_PATH=$(command -v "$PYTHON_CANDIDATE")

            if python_can_create_venv "$PYTHON_PATH"
            then
                PYTHON_BIN="$PYTHON_PATH"
                return 0
            fi
        fi
    done

    return 1
}

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

if ! detect_python_venv
then

    echo "Módulo venv do Python não encontrado."

    if [ -f /etc/debian_version ]
    then

        echo "Instalando suporte a ambiente virtual no Debian/Ubuntu..."

        sudo apt update
        sudo apt install -y python3 python3-venv python3-pip

    elif [ -f /etc/redhat-release ]
    then

        echo "Instalando suporte a ambiente virtual no RHEL/Rocky..."

        sudo dnf install -y python3 python3-pip

    else

        echo "Distribuição não suportada."
        echo "Instale o módulo venv do Python manualmente."

        exit 1

    fi

fi

if ! detect_python_venv
then

    echo
    echo "ERRO: Nenhuma versão do Python instalada consegue criar ambiente virtual."
    echo
    echo "Se o comando python3 aponta para uma versão manual, como Python 3.14,"
    echo "instale o pacote venv dessa versão ou ajuste o python3 para usar"
    echo "a versão Python padrão da distribuição."
    echo

    exit 1

fi

echo "Python OK: $PYTHON_BIN"
echo

# ============================================================
# SSH
# ============================================================

echo "Verificando cliente SSH..."

if ! command -v ssh >/dev/null 2>&1
then

    echo "Cliente SSH não encontrado."

    if [ -f /etc/debian_version ]
    then

        echo "Instalando openssh-client no Debian/Ubuntu..."

        sudo apt update
        sudo apt install -y openssh-client

    elif [ -f /etc/redhat-release ]
    then

        echo "Instalando openssh-clients no RHEL/Rocky..."

        sudo dnf install -y openssh-clients

    else

        echo "Distribuição não suportada."
        echo "Instale o cliente SSH manualmente."

        exit 1

    fi

fi

if ! command -v ssh >/dev/null 2>&1
then

    echo "ERRO: Cliente SSH não disponível."
    exit 1

fi

echo "SSH OK: $(command -v ssh)"
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

echo "=================================="
echo " CONFIGURAÇÃO TELEGRAM"
echo "=================================="
echo
echo "Para usar Telegram, crie um bot no @BotFather e informe o token."
echo "Deixe em branco para não configurar alertas por Telegram agora."
echo

read -p "Token do bot Telegram: " TELEGRAM_BOT_TOKEN

TELEGRAM_CHAT_ID=""

if [ -n "$TELEGRAM_BOT_TOKEN" ]
then

    echo
    echo "Envie uma mensagem para o bot antes de informar o chat_id."
    echo "Para grupos, adicione o bot ao grupo e use o chat_id do grupo."
    echo

    while true
    do

        read -p "Chat ID do Telegram: " TELEGRAM_CHAT_ID

        if [ -n "$TELEGRAM_CHAT_ID" ]
        then
            break
        fi

        echo "Chat ID não pode estar vazio quando o token foi informado."

    done

fi

echo

cat > .env << EOF
SMTP_SERVER="$SMTP_SERVER"
SMTP_PORT="$SMTP_PORT"
SMTP_TLS="$SMTP_TLS"
SMTP_USER="$SMTP_USER"
SMTP_PASS_ENC_FILE="$SMTP_PASS_ENC_FILE"
SMTP_PASS_KEY_FILE="$SMTP_PASS_KEY_FILE"
SMTP_TO="$SMTP_TO"
TELEGRAM_BOT_TOKEN="$TELEGRAM_BOT_TOKEN"
TELEGRAM_CHAT_ID="$TELEGRAM_CHAT_ID"
INTERVALO_VERIFICACAO="5"
FALHAS_PARA_ALERTA="3"
ALERTA_EMAIL_INTERVALO_HORAS="24"
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

SMTP_TEST_SERVER="$SMTP_SERVER" \
SMTP_TEST_PORT="$SMTP_PORT" \
SMTP_TEST_USER="$SMTP_USER" \
SMTP_TEST_PASSWORD="$SMTP_PASS" \
SMTP_TEST_TLS="$SMTP_TLS" \
"$PYTHON_BIN" << 'EOF'
import smtplib
import sys
import os

server = os.environ["SMTP_TEST_SERVER"]
port = int(os.environ["SMTP_TEST_PORT"])
user = os.environ["SMTP_TEST_USER"]
password = os.environ["SMTP_TEST_PASSWORD"]
tls = os.environ["SMTP_TEST_TLS"]

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
# TESTE TELEGRAM
# ============================================================

if [ -n "$TELEGRAM_BOT_TOKEN" ]
then

    echo "Testando envio Telegram..."

    TELEGRAM_TEST_BOT_TOKEN="$TELEGRAM_BOT_TOKEN" \
    TELEGRAM_TEST_CHAT_ID="$TELEGRAM_CHAT_ID" \
    "$PYTHON_BIN" << 'EOF'
import os
import sys
import urllib.parse
import urllib.request

token = os.environ["TELEGRAM_TEST_BOT_TOKEN"]
chat_id = os.environ["TELEGRAM_TEST_CHAT_ID"]

data = urllib.parse.urlencode({
    "chat_id": chat_id,
    "text": "SSHMON: teste de integração Telegram OK"
}).encode("utf-8")

url = f"https://api.telegram.org/bot{token}/sendMessage"

try:
    request = urllib.request.Request(
        url,
        data=data,
        method="POST"
    )

    with urllib.request.urlopen(
        request,
        timeout=20
    ) as response:

        if response.status != 200:
            print(f"Telegram retornou HTTP {response.status}")
            sys.exit(1)

    print("Telegram OK")

except Exception as e:
    print("Falha no teste Telegram:")
    print(e)
    sys.exit(1)
EOF

    echo "Telegram validado com sucesso."
    echo

fi

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
sudo mkdir -p "$SECRET_DIR"
sudo mkdir -p /var/log/sshmon
sudo mkdir -p /home/sshmon/.ssh

sudo chown root:sshmon "$SECRET_DIR"
sudo chmod 750 "$SECRET_DIR"

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
# AMBIENTE VIRTUAL
# ============================================================

echo "Criando ambiente virtual Python..."

sudo -u sshmon "$PYTHON_BIN" -m venv "$APP_DIR/venv"

VENV_PYTHON="$APP_DIR/venv/bin/python"

if ! sudo -u sshmon "$VENV_PYTHON" -m pip --version >/dev/null 2>&1
then

    echo "pip não encontrado no ambiente virtual. Tentando instalar com ensurepip..."

    sudo -u sshmon "$VENV_PYTHON" -m ensurepip --upgrade

fi

if ! sudo -u sshmon "$VENV_PYTHON" -m pip --version >/dev/null 2>&1
then

    echo
    echo "ERRO: pip não disponível no ambiente virtual."
    echo "Instale o suporte a pip/venv da versão Python em uso e execute novamente."
    echo

    exit 1

fi

echo "Atualizando pip..."

sudo -u sshmon "$VENV_PYTHON" -m pip install --upgrade pip

echo "Instalando dependências..."

sudo -u sshmon "$VENV_PYTHON" -m pip install \
    -r "$APP_DIR/requirements.txt"

echo "Validando dependências Python..."

sudo -u sshmon "$VENV_PYTHON" << 'EOF'
import cryptography
import dotenv
import paramiko
EOF

echo "Criptografando senha SMTP..."

SMTP_SECRET_TMP=$(mktemp -d /tmp/sshmon-secret.XXXXXX)

SMTP_SECRET_TMP="$SMTP_SECRET_TMP" \
SMTP_SECRET_PASSWORD="$SMTP_PASS" \
"$VENV_PYTHON" << 'EOF'
import os
from cryptography.fernet import Fernet

tmp_dir = os.environ["SMTP_SECRET_TMP"]
password = os.environ["SMTP_SECRET_PASSWORD"].encode("utf-8")

key = Fernet.generate_key()
encrypted_password = Fernet(key).encrypt(password)

with open(
    os.path.join(tmp_dir, "smtp_pass.key"),
    "wb"
) as arquivo:
    arquivo.write(key + b"\n")

with open(
    os.path.join(tmp_dir, "smtp_pass.enc"),
    "wb"
) as arquivo:
    arquivo.write(encrypted_password + b"\n")
EOF

sudo install -o root -g sshmon -m 640 "$SMTP_SECRET_TMP/smtp_pass.enc" "$SMTP_PASS_ENC_FILE"
sudo install -o root -g sshmon -m 640 "$SMTP_SECRET_TMP/smtp_pass.key" "$SMTP_PASS_KEY_FILE"

rm -rf "$SMTP_SECRET_TMP"
SMTP_SECRET_TMP=""
unset SMTP_PASS

echo "Validando leitura da senha criptografada..."

sudo -u sshmon env \
SMTP_PASS_ENC_FILE="$SMTP_PASS_ENC_FILE" \
SMTP_PASS_KEY_FILE="$SMTP_PASS_KEY_FILE" \
"$VENV_PYTHON" << 'EOF'
import os
import sys
from cryptography.fernet import Fernet

with open(
    os.environ["SMTP_PASS_KEY_FILE"],
    "rb"
) as arquivo:
    key = arquivo.read().strip()

with open(
    os.environ["SMTP_PASS_ENC_FILE"],
    "rb"
) as arquivo:
    encrypted_password = arquivo.read().strip()

password = Fernet(key).decrypt(encrypted_password)

if not password:
    sys.exit(1)
EOF

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
echo "  Configuração: $APP_DIR/.env"
echo "  Senha criptografada: $SMTP_PASS_ENC_FILE"
echo "  Chave local: $SMTP_PASS_KEY_FILE"
echo
echo "Chaves SSH:"
echo "  Após a instalação, coloque suas chaves .pem ou .ppk em:"
echo "  /home/sshmon/.ssh/"
echo
echo "  Depois ajuste as permissões:"
echo "  sudo chown sshmon:sshmon /home/sshmon/.ssh/*.pem /home/sshmon/.ssh/*.ppk"
echo "  sudo chmod 600 /home/sshmon/.ssh/*.pem /home/sshmon/.ssh/*.ppk"
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
