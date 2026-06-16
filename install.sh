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
# MÉTODO DE ALERTA
# ============================================================

SMTP_ENABLED="0"
TELEGRAM_ENABLED="0"
SMTP_SERVER=""
SMTP_PORT=""
SMTP_TLS=""
SMTP_USER=""
SMTP_PASS=""
SMTP_TO=""
TELEGRAM_BOT_TOKEN=""
TELEGRAM_CHAT_ID=""

while true
do
    echo "=================================="
    echo " MÉTODO DE ALERTA"
    echo "=================================="
    echo
    echo "1 - SMTP / E-mail"
    echo "2 - Telegram / BotFather"
    echo "3 - Ambos"
    echo
    read -p "Escolha [1]: " ALERTA_OPCAO
    ALERTA_OPCAO=${ALERTA_OPCAO:-1}

    case "$ALERTA_OPCAO" in
        1)
            SMTP_ENABLED="1"
            TELEGRAM_ENABLED="0"
            break
            ;;
        2)
            SMTP_ENABLED="0"
            TELEGRAM_ENABLED="1"
            break
            ;;
        3)
            SMTP_ENABLED="1"
            TELEGRAM_ENABLED="1"
            break
            ;;
        *)
            echo "Opção inválida. Escolha 1, 2 ou 3."
            echo
            ;;
    esac
done

echo

# ============================================================
# SMTP
# ============================================================

if [ "$SMTP_ENABLED" = "1" ]
then

    echo "=================================="
    echo " CONFIGURAÇÃO SMTP"
    echo "=================================="
    echo

    while true
    do
        read -p "Servidor SMTP: " SMTP_SERVER

        if [ -n "$SMTP_SERVER" ]
        then
            break
        fi

        echo "Servidor SMTP não pode estar vazio."
    done

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

fi

# ============================================================
# TELEGRAM / BOTFATHER
# ============================================================

if [ "$TELEGRAM_ENABLED" = "1" ]
then

    echo "=================================="
    echo " CONFIGURAÇÃO TELEGRAM"
    echo "=================================="
    echo
    echo "Crie um bot no Telegram pelo @BotFather e informe o token."
    echo

    while true
    do
        read -p "Token do bot Telegram: " TELEGRAM_BOT_TOKEN

        if [ -n "$TELEGRAM_BOT_TOKEN" ]
        then
            break
        fi

        echo "Token do Telegram não pode estar vazio."
    done

    echo
    echo "Envie uma mensagem para o bot antes de informar o chat_id."
    echo "Se for uma conversa direta com o bot, abra o bot e envie /start."
    echo "Para grupos, adicione o bot ao grupo e use o chat_id do grupo."
    echo
    echo "URL para consultar updates do bot:"
    echo "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/getUpdates"
    echo

    while true
    do

        read -p "Você já enviou /start para o bot? [s/N]: " TELEGRAM_START_CONFIRMADO

        case "$TELEGRAM_START_CONFIRMADO" in
            [Ss]) break ;;
        esac

        echo "Abra o bot no Telegram, envie /start e depois confirme aqui."

    done

    read -p "Tentar buscar o chat_id automaticamente agora? [S/n]: " TELEGRAM_BUSCAR_CHAT_ID

    case "$TELEGRAM_BUSCAR_CHAT_ID" in
        [Nn])
            TELEGRAM_CHAT_ID=""
            ;;
        *)
            echo "Buscando chat_id em getUpdates..."

            TELEGRAM_CHAT_ID=$(
                TELEGRAM_GETUPDATES_TOKEN="$TELEGRAM_BOT_TOKEN" \
                "$PYTHON_BIN" << 'EOF'
import json
import os
import sys
import urllib.request

token = os.environ["TELEGRAM_GETUPDATES_TOKEN"]
url = f"https://api.telegram.org/bot{token}/getUpdates"


def extract_chat(update):
    for key in [
        "message",
        "edited_message",
        "channel_post",
        "edited_channel_post"
    ]:
        item = update.get(key)

        if isinstance(item, dict):
            chat = item.get("chat")

            if isinstance(chat, dict) and chat.get("id") is not None:
                return chat

    callback_query = update.get("callback_query")

    if isinstance(callback_query, dict):
        message = callback_query.get("message")

        if isinstance(message, dict):
            chat = message.get("chat")

            if isinstance(chat, dict) and chat.get("id") is not None:
                return chat

    return None


try:
    with urllib.request.urlopen(
        url,
        timeout=20
    ) as response:
        data = json.load(response)

except Exception as erro:
    print(
        f"Erro ao consultar getUpdates: {erro}",
        file=sys.stderr
    )
    sys.exit(1)

if not data.get("ok"):
    print(
        data.get("description", "Resposta invalida do Telegram."),
        file=sys.stderr
    )
    sys.exit(1)

for update in reversed(data.get("result", [])):
    chat = extract_chat(update)

    if chat:
        print(chat["id"])
        sys.exit(0)

print(
    "Nenhum chat_id encontrado. Envie /start ao bot e tente novamente.",
    file=sys.stderr
)
sys.exit(1)
EOF
            ) || TELEGRAM_CHAT_ID=""

            if [ -n "$TELEGRAM_CHAT_ID" ]
            then
                echo "Chat ID encontrado: $TELEGRAM_CHAT_ID"
            else
                echo "Não foi possível detectar o chat_id automaticamente."
                echo "Abra a URL acima no navegador e procure por chat.id."
            fi
            ;;
    esac

    while true
    do

        if [ -n "$TELEGRAM_CHAT_ID" ]
        then
            break
        fi

        read -p "Chat ID do Telegram: " TELEGRAM_CHAT_ID

        if [ -n "$TELEGRAM_CHAT_ID" ]
        then
            break
        fi

        echo "Chat ID não pode estar vazio."

    done

    echo

fi

cat > .env << EOF
ALERTA_METODO="$ALERTA_OPCAO"
SMTP_ENABLED="$SMTP_ENABLED"
TELEGRAM_ENABLED="$TELEGRAM_ENABLED"
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

if [ "$SMTP_ENABLED" = "1" ]
then

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

else

    echo "SMTP desativado. Pulando teste SMTP."
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

if [ "$TELEGRAM_ENABLED" = "1" ]
then

    echo "Instalando biblioteca telebot..."

    sudo -u sshmon "$VENV_PYTHON" -m pip install telebot

fi

echo "Validando dependências Python..."

sudo -u sshmon "$VENV_PYTHON" << 'EOF'
import cryptography
import dotenv
import paramiko
EOF

if [ "$TELEGRAM_ENABLED" = "1" ]
then

    echo "Validando biblioteca telebot..."

    sudo -u sshmon "$VENV_PYTHON" << 'EOF'
import telebot
EOF

fi

# ============================================================
# TESTE TELEGRAM
# ============================================================

if [ "$TELEGRAM_ENABLED" = "1" ]
then

    while true
    do

        echo "Testando envio Telegram com telebot..."

        if sudo -u sshmon env \
        TELEGRAM_TEST_BOT_TOKEN="$TELEGRAM_BOT_TOKEN" \
        TELEGRAM_TEST_CHAT_ID="$TELEGRAM_CHAT_ID" \
        "$VENV_PYTHON" << 'EOF'
import os
import sys
import telebot

token = os.environ["TELEGRAM_TEST_BOT_TOKEN"]
chat_id = os.environ["TELEGRAM_TEST_CHAT_ID"]

try:
    bot = telebot.TeleBot(
        token,
        parse_mode=None
    )

    bot.send_message(
        chat_id,
        "SSHMON: teste de integração Telegram OK"
    )

    print("Telegram OK")

except Exception as e:
    print("Falha no teste Telegram:")
    print(e)
    print("Confirme se o token está correto, se o chat_id é válido e se você enviou /start para o bot.")
    sys.exit(1)
EOF
        then

            echo "Telegram validado com sucesso."
            echo
            break

        fi

        echo
        echo "O teste Telegram falhou."
        echo "Se o chat_id mudou, se o bot foi bloqueado/desbloqueado ou se é uma conversa nova,"
        echo "envie /start novamente para o bot e tente atualizar o chat_id."
        echo
        echo "URL para consultar updates do bot:"
        echo "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/getUpdates"
        echo

        read -p "Tentar buscar um novo chat_id automaticamente? [S/n]: " TELEGRAM_REBUSCAR_CHAT_ID

        case "$TELEGRAM_REBUSCAR_CHAT_ID" in
            [Nn])
                read -p "Informar um novo chat_id manualmente? [s/N]: " TELEGRAM_CHAT_ID_MANUAL

                case "$TELEGRAM_CHAT_ID_MANUAL" in
                    [Ss])
                        TELEGRAM_CHAT_ID=""
                        ;;
                    *)
                        echo "Instalação interrompida. Corrija o Telegram e execute novamente."
                        exit 1
                        ;;
                esac
                ;;
            *)
                echo "Buscando chat_id em getUpdates..."

                TELEGRAM_CHAT_ID=$(
                    TELEGRAM_GETUPDATES_TOKEN="$TELEGRAM_BOT_TOKEN" \
                    "$PYTHON_BIN" << 'EOF'
import json
import os
import sys
import urllib.request

token = os.environ["TELEGRAM_GETUPDATES_TOKEN"]
url = f"https://api.telegram.org/bot{token}/getUpdates"


def extract_chat(update):
    for key in [
        "message",
        "edited_message",
        "channel_post",
        "edited_channel_post"
    ]:
        item = update.get(key)

        if isinstance(item, dict):
            chat = item.get("chat")

            if isinstance(chat, dict) and chat.get("id") is not None:
                return chat

    callback_query = update.get("callback_query")

    if isinstance(callback_query, dict):
        message = callback_query.get("message")

        if isinstance(message, dict):
            chat = message.get("chat")

            if isinstance(chat, dict) and chat.get("id") is not None:
                return chat

    return None


try:
    with urllib.request.urlopen(
        url,
        timeout=20
    ) as response:
        data = json.load(response)

except Exception as erro:
    print(
        f"Erro ao consultar getUpdates: {erro}",
        file=sys.stderr
    )
    sys.exit(1)

if not data.get("ok"):
    print(
        data.get("description", "Resposta invalida do Telegram."),
        file=sys.stderr
    )
    sys.exit(1)

for update in reversed(data.get("result", [])):
    chat = extract_chat(update)

    if chat:
        print(chat["id"])
        sys.exit(0)

sys.exit(1)
EOF
                ) || TELEGRAM_CHAT_ID=""

                if [ -n "$TELEGRAM_CHAT_ID" ]
                then
                    echo "Novo Chat ID encontrado: $TELEGRAM_CHAT_ID"
                else
                    echo "Não foi possível detectar automaticamente."
                fi
                ;;
        esac

        while true
        do

            if [ -n "$TELEGRAM_CHAT_ID" ]
            then
                break
            fi

            read -p "Novo Chat ID do Telegram: " TELEGRAM_CHAT_ID

            if [ -n "$TELEGRAM_CHAT_ID" ]
            then
                break
            fi

            echo "Chat ID não pode estar vazio."

        done

        TELEGRAM_ENV_CHAT_ID="$TELEGRAM_CHAT_ID" "$PYTHON_BIN" << 'EOF'
import os

chat_id = os.environ["TELEGRAM_ENV_CHAT_ID"]

for path in [".env"]:
    with open(
        path,
        "r",
        encoding="utf-8"
    ) as arquivo:
        linhas = arquivo.readlines()

    with open(
        path,
        "w",
        encoding="utf-8"
    ) as arquivo:
        for linha in linhas:
            if linha.startswith("TELEGRAM_CHAT_ID="):
                arquivo.write(f'TELEGRAM_CHAT_ID="{chat_id}"\n')
            else:
                arquivo.write(linha)
EOF

        sudo cp .env "$APP_DIR/"
        sudo chmod 600 "$APP_DIR/.env"
        sudo chown sshmon:sshmon "$APP_DIR/.env"

    done

else

    echo "Telegram desativado. Pulando instalação e teste do telebot."
    echo

fi

if [ "$SMTP_ENABLED" = "1" ]
then

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

else

    echo "SMTP desativado. Não será criada senha SMTP criptografada."

fi

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
echo "Alertas:"
echo "  Configuração: $APP_DIR/.env"
if [ "$SMTP_ENABLED" = "1" ]
then
    echo "  SMTP: ativado"
    echo "  Senha criptografada: $SMTP_PASS_ENC_FILE"
    echo "  Chave local: $SMTP_PASS_KEY_FILE"
else
    echo "  SMTP: desativado"
fi
if [ "$TELEGRAM_ENABLED" = "1" ]
then
    echo "  Telegram/BotFather: ativado"
else
    echo "  Telegram/BotFather: desativado"
fi
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
