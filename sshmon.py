#!/usr/bin/env python3

import json
import os
import time
import socket
import traceback
import smtplib
from datetime import datetime
from email.message import EmailMessage
from concurrent.futures import (
    ThreadPoolExecutor,
    as_completed
)

import paramiko
from dotenv import load_dotenv


# ============================================================
# CONFIGURAÇÕES
# ============================================================

INTERVALO_VERIFICACAO = 5
FALHAS_PARA_ALERTA = 3

HOSTS_FILE = "hosts.json"

LOG_DIR = "/var/log/sshmon"

SUCCESS_LOG = os.path.join(
    LOG_DIR,
    "successful.log"
)

UNSUCCESS_LOG = os.path.join(
    LOG_DIR,
    "unsuccessful.log"
)

ACCESSDENIED_LOG = os.path.join(
    LOG_DIR,
    "accessdenied.log"
)

WARNING_LOG = os.path.join(
    LOG_DIR,
    "warnings.log"
)

MAX_LOG_SIZE_MB = 10

SSH_TIMEOUT = 5


# ============================================================
# VARIÁVEIS SMTP
# ============================================================

load_dotenv()

def get_int_env(
    nome,
    padrao,
    minimo=1
):

    valor = os.getenv(
        nome
    )

    if not valor:
        return padrao

    try:

        numero = int(
            valor
        )

        if numero < minimo:
            raise ValueError

        return numero

    except ValueError:

        return padrao


INTERVALO_VERIFICACAO = get_int_env(
    "INTERVALO_VERIFICACAO",
    INTERVALO_VERIFICACAO
)

FALHAS_PARA_ALERTA = get_int_env(
    "FALHAS_PARA_ALERTA",
    FALHAS_PARA_ALERTA
)

MAX_LOG_SIZE_MB = get_int_env(
    "MAX_LOG_SIZE_MB",
    MAX_LOG_SIZE_MB
)

SSH_TIMEOUT = get_int_env(
    "SSH_TIMEOUT",
    SSH_TIMEOUT
)

SMTP_SERVER = os.getenv(
    "SMTP_SERVER"
)

SMTP_PORT = int(
    get_int_env(
        "SMTP_PORT",
        587
    )
)

SMTP_TLS = os.getenv(
    "SMTP_TLS",
    "starttls"
).lower()

SMTP_USER = os.getenv(
    "SMTP_USER"
)

SMTP_PASS_FILE = os.getenv(
    "SMTP_PASS_FILE"
)


def read_secret_file(path):

    if not path:
        return None

    try:

        with open(
            path,
            "r",
            encoding="utf-8"
        ) as arquivo:

            return arquivo.read().strip()

    except OSError:
        return None


SMTP_PASS = os.getenv(
    "SMTP_PASS"
) or read_secret_file(
    SMTP_PASS_FILE
)

SMTP_TO = os.getenv(
    "SMTP_TO"
)


def smtp_configured():

    return all([
        SMTP_SERVER,
        SMTP_USER,
        SMTP_PASS,
        SMTP_TO
    ])


# ============================================================
# UTILITÁRIOS
# ============================================================

def timestamp():

    return datetime.now().strftime(
        "%Y-%m-%d %H:%M:%S"
    )


def ensure_log_dir():

    os.makedirs(
        LOG_DIR,
        exist_ok=True
    )


def rotate_log(logfile):

    try:

        if not os.path.exists(logfile):
            return

        tamanho_mb = (
            os.path.getsize(logfile)
            / 1024
            / 1024
        )

        if tamanho_mb < MAX_LOG_SIZE_MB:
            return

        backup = logfile + ".1"

        if os.path.exists(backup):
            os.remove(backup)

        os.rename(
            logfile,
            backup
        )

    except Exception:
        pass


def write_log(
    logfile,
    message
):

    try:

        rotate_log(logfile)

        with open(
            logfile,
            "a",
            encoding="utf-8"
        ) as arquivo:

            arquivo.write(
                f"{timestamp()} - {message}\n"
            )

    except Exception:
        pass


def log_success(msg):

    write_log(
        SUCCESS_LOG,
        msg
    )


def log_failure(msg):

    write_log(
        UNSUCCESS_LOG,
        msg
    )


def log_access_denied(msg):

    write_log(
        ACCESSDENIED_LOG,
        msg
    )


def log_warning(msg):

    write_log(
        WARNING_LOG,
        msg
    )


# ============================================================
# INICIALIZAÇÃO DOS LOGS
# ============================================================

def initialize_logs():

    ensure_log_dir()

    with open(
        SUCCESS_LOG,
        "w",
        encoding="utf-8"
    ):
        pass

    for arquivo in [
        UNSUCCESS_LOG,
        ACCESSDENIED_LOG,
        WARNING_LOG
    ]:

        if not os.path.exists(
            arquivo
        ):

            open(
                arquivo,
                "a"
            ).close()


# ============================================================
# EMAIL
# ============================================================

def send_email(
    subject,
    body
):

    if not smtp_configured():

        log_warning(
            "SMTP não configurado. Alerta por e-mail ignorado."
        )

        return

    smtp = None

    try:

        email = EmailMessage()

        email["From"] = SMTP_USER
        email["To"] = SMTP_TO
        email["Subject"] = subject

        email.set_content(body)

        if SMTP_TLS == "ssl":

            smtp = smtplib.SMTP_SSL(
                SMTP_SERVER,
                SMTP_PORT,
                timeout=30
            )

        else:

            smtp = smtplib.SMTP(
                SMTP_SERVER,
                SMTP_PORT,
                timeout=30
            )

            smtp.ehlo()
            smtp.starttls()
            smtp.ehlo()

            smtp.login(
                SMTP_USER,
                SMTP_PASS
            )

        smtp.send_message(
            email
        )

    except Exception as erro:

        log_warning(
            f"SMTP ERROR: {erro}"
        )

    finally:

        try:

            if smtp:
                smtp.quit()

        except Exception:
            pass

# ============================================================
# HOSTS.JSON
# ============================================================

_hosts_cache = None
_hosts_mtime = None


def load_hosts():

    global _hosts_cache
    global _hosts_mtime

    try:

        mtime = os.path.getmtime(
            HOSTS_FILE
        )

        if (
            _hosts_cache is None
            or
            _hosts_mtime != mtime
        ):

            with open(
                HOSTS_FILE,
                "r",
                encoding="utf-8"
            ) as arquivo:

                dados = json.load(
                    arquivo
                )

            hosts_validos = []

            for indice, host in enumerate(
                dados.get(
                    "hosts",
                    []
                ),
                start=1
            ):

                nome = host.get(
                    "nome"
                )
                ip = host.get(
                    "ip"
                )
                usuario = host.get(
                    "usuario"
                )

                if not ip or not usuario:

                    log_warning(
                        f"Host #{indice} ignorado: "
                        "ip e usuario são obrigatórios."
                    )

                    continue

                if not host.get("senha") and not host.get("certificado"):

                    log_warning(
                        f"Host {nome or ip} ignorado: "
                        "configure senha ou certificado."
                    )

                    continue

                host[
                    "nome"
                ] = nome or ip

                hosts_validos.append(
                    host
                )

            _hosts_cache = hosts_validos

            _hosts_mtime = mtime

            log_warning(
                f"hosts.json recarregado "
                f"({len(hosts_validos)} host(s) válido(s))"
            )

        return _hosts_cache

    except Exception as erro:

        log_warning(
            f"Erro carregando hosts.json: {erro}"
        )

        return []


# ============================================================
# SSH
# ============================================================

def ssh_connect(
    host
):

    nome = host.get(
        "nome",
        "UNKNOWN"
    )

    ip = host.get(
        "ip"
    )

    usuario = host.get(
        "usuario"
    )

    senha = host.get(
        "senha"
    )

    certificado = host.get(
        "certificado"
    )

    inicio = time.time()

    client = None

    try:

        client = paramiko.SSHClient()

        client.set_missing_host_key_policy(
            paramiko.AutoAddPolicy()
        )

        parametros = {

            "hostname": ip,

            "username": usuario,

            "timeout":
                SSH_TIMEOUT,

            "auth_timeout":
                SSH_TIMEOUT,

            "banner_timeout":
                SSH_TIMEOUT,

            "look_for_keys":
                False,

            "allow_agent":
                False
        }

        # ====================================================
        # PRIORIDADE:
        #
        # certificado > senha
        # ====================================================

        if certificado:

            parametros[
                "key_filename"
            ] = os.path.expanduser(
                certificado
            )

        elif senha:

            parametros[
                "password"
            ] = senha

        else:

            return {

                "ok": False,

                "tipo":
                    "access_denied",

                "nome":
                    nome,

                "ip":
                    ip,

                "mensagem":
                    "No authentication method configured"
            }

        client.connect(
            **parametros
        )

        stdin, stdout, stderr = (
            client.exec_command(
                "true",
                timeout=SSH_TIMEOUT
            )
        )

        retorno = (
            stdout.channel
            .recv_exit_status()
        )

        tempo = round(
            time.time() - inicio,
            3
        )

        if retorno == 0:

            return {

                "ok": True,

                "nome":
                    nome,

                "ip":
                    ip,

                "tempo":
                    tempo
            }

        return {

            "ok": False,

            "tipo":
                "ssh",

            "nome":
                nome,

            "ip":
                ip,

            "mensagem":
                f"Exit code {retorno}"
        }

    except paramiko.AuthenticationException:

        return {

            "ok": False,

            "tipo":
                "access_denied",

            "nome":
                nome,

            "ip":
                ip,

            "mensagem":
                "Authentication failed"
        }

    except paramiko.PasswordRequiredException:

        return {

            "ok": False,

            "tipo":
                "access_denied",

            "nome":
                nome,

            "ip":
                ip,

            "mensagem":
                "Private key requires passphrase"
        }

    except paramiko.BadHostKeyException:

        return {

            "ok": False,

            "tipo":
                "access_denied",

            "nome":
                nome,

            "ip":
                ip,

            "mensagem":
                "Bad host key"
        }

    except paramiko.SSHException as erro:

        return {

            "ok": False,

            "tipo":
                "ssh",

            "nome":
                nome,

            "ip":
                ip,

            "mensagem":
                str(erro)
        }

    except socket.timeout:

        return {

            "ok": False,

            "tipo":
                "ssh",

            "nome":
                nome,

            "ip":
                ip,

            "mensagem":
                "Connection timeout"
        }

    except socket.gaierror:

        return {

            "ok": False,

            "tipo":
                "ssh",

            "nome":
                nome,

            "ip":
                ip,

            "mensagem":
                "DNS resolution failed"
        }

    except Exception as erro:

        return {

            "ok": False,

            "tipo":
                "ssh",

            "nome":
                nome,

            "ip":
                ip,

            "mensagem":
                str(erro)
        }

    finally:

        try:

            if client:
                client.close()

        except Exception:
            pass


# ============================================================
# THREAD WORKER
# ============================================================

def check_host(
    host
):

    try:

        return ssh_connect(
            host
        )

    except Exception as erro:

        return {

            "ok": False,

            "tipo":
                "ssh",

            "nome":
                host.get("nome"),

            "ip":
                host.get("ip"),

            "mensagem":
                f"Worker exception: {erro}"
        }

# ============================================================
# ESTADO DOS HOSTS
# ============================================================

host_status = {}


def initialize_host_status():

    hosts = load_hosts()

    for host in hosts:

        ip = host.get(
            "ip"
        )

        host_status[ip] = {

            "online": True,

            "failures": 0,

            "last_state": "UNKNOWN"
        }


# ============================================================
# ALERTAS
# ============================================================

def notify_host_offline(
    nome,
    ip
):

    assunto = (
        f"[OFFLINE] {nome}"
    )

    mensagem = (
        f"Host: {nome}\n"
        f"IP: {ip}\n\n"
        f"O host não responde mais "
        f"via SSH."
    )

    send_email(
        assunto,
        mensagem
    )


def notify_host_recovered(
    nome,
    ip
):

    assunto = (
        f"[RECUPERADO] {nome}"
    )

    mensagem = (
        f"Host: {nome}\n"
        f"IP: {ip}\n\n"
        f"O host voltou a responder "
        f"via SSH."
    )

    send_email(
        assunto,
        mensagem
    )


# ============================================================
# PROCESSAMENTO DOS RESULTADOS
# ============================================================

def process_result(
    result
):

    nome = result["nome"]
    ip = result["ip"]

    if ip not in host_status:

        host_status[ip] = {

            "online": True,

            "failures": 0,

            "last_state": "UNKNOWN"
        }

    status = host_status[ip]

    # ========================================================
    # SUCESSO
    # ========================================================

    if result["ok"]:

        tempo = result["tempo"]

        log_success(
            f"{nome} ({ip}) "
            f"- OK "
            f"- {tempo}s"
        )

        if not status["online"]:

            log_warning(
                f"HOST RECUPERADO "
                f"- {nome} "
                f"({ip})"
            )

            notify_host_recovered(
                nome,
                ip
            )

        status["online"] = True

        status["failures"] = 0

        status["last_state"] = "ONLINE"

        return

    # ========================================================
    # FALHA DE AUTENTICAÇÃO
    # ========================================================

    if result["tipo"] == "access_denied":

        log_access_denied(
            f"{nome} ({ip}) "
            f"- {result['mensagem']}"
        )

    else:

        log_failure(
            f"{nome} ({ip}) "
            f"- {result['mensagem']}"
        )

    # ========================================================
    # CONTADOR DE FALHAS
    # ========================================================

    status["failures"] += 1

    if (
        status["online"]
        and
        status["failures"]
        >= FALHAS_PARA_ALERTA
    ):

        status["online"] = False

        status["last_state"] = "OFFLINE"

        log_warning(
            f"HOST OFFLINE "
            f"- {nome} "
            f"({ip}) "
            f"- {status['failures']} "
            f"falhas consecutivas"
        )

        notify_host_offline(
            nome,
            ip
        )


# ============================================================
# CICLO DE MONITORAMENTO
# ============================================================

def monitor_cycle():

    hosts = load_hosts()

    if not hosts:

        log_warning(
            "Nenhum host carregado."
        )

        return

    ips_ativos = {
        host.get(
            "ip"
        )
        for host in hosts
    }

    for ip in list(
        host_status
    ):

        if ip not in ips_ativos:

            host_status.pop(
                ip,
                None
            )

            log_warning(
                f"Host removido do monitoramento: {ip}"
            )

    all_ok = True

    with ThreadPoolExecutor(
        max_workers=min(
            len(hosts),
            50
        )
    ) as executor:

        futures = {

            executor.submit(
                check_host,
                host
            ): host

            for host in hosts
        }

        for future in as_completed(
            futures
        ):

            try:

                result = (
                    future.result()
                )

                if not result["ok"]:
                    all_ok = False

                process_result(
                    result
                )

            except Exception as erro:

                all_ok = False

                log_warning(
                    f"Thread exception: "
                    f"{erro}"
                )

                log_warning(
                    traceback.format_exc()
                )

    # ========================================================
    # RELATÓRIO GERAL
    # ========================================================

    if all_ok:

        log_success(
            "CONEXÃO BEM SUCEDIDA "
            "COM TODOS OS HOSTS"
        )

# ============================================================
# INICIALIZAÇÃO
# ============================================================

def startup_check():

    try:

        hosts = load_hosts()

        if not hosts:

            log_warning(
                "Nenhum host encontrado "
                "durante inicialização."
            )

            return

        log_warning(
            f"Inicializando monitor "
            f"com {len(hosts)} host(s)."
        )

        falhas = []

        with ThreadPoolExecutor(
            max_workers=min(
                len(hosts),
                50
            )
        ) as executor:

            futures = {

                executor.submit(
                    check_host,
                    host
                ): host

                for host in hosts
            }

            for future in as_completed(
                futures
            ):

                try:

                    result = (
                        future.result()
                    )

                    if not result["ok"]:

                        falhas.append(
                            result
                        )

                except Exception as erro:

                    falhas.append({

                        "nome":
                            "UNKNOWN",

                        "ip":
                            "UNKNOWN",

                        "mensagem":
                            str(erro)
                    })

        if not falhas:

            log_success(
                "CONEXÃO BEM SUCEDIDA "
                "COM TODOS OS HOSTS"
            )

        else:

            for host in falhas:

                nome = host.get(
                    "nome",
                    "UNKNOWN"
                )

                ip = host.get(
                    "ip",
                    "UNKNOWN"
                )

                mensagem = host.get(
                    "mensagem",
                    "UNKNOWN ERROR"
                )

                log_failure(
                    f"{nome} ({ip}) "
                    f"- FALHA INICIAL "
                    f"- {mensagem}"
                )

    except Exception as erro:

        log_warning(
            f"Erro startup_check: "
            f"{erro}"
        )

        log_warning(
            traceback.format_exc()
        )


# ============================================================
# LOOP PRINCIPAL
# ============================================================

def run():

    initialize_logs()

    initialize_host_status()

    startup_check()

    log_warning(
        "SSHMON iniciado."
    )

    while True:

        try:

            monitor_cycle()

        except Exception as erro:

            log_warning(
                f"Erro monitor_cycle: "
                f"{erro}"
            )

            log_warning(
                traceback.format_exc()
            )

        time.sleep(
            INTERVALO_VERIFICACAO
        )


# ============================================================
# MAIN
# ============================================================

if __name__ == "__main__":

    while True:

        try:

            run()

        except KeyboardInterrupt:

            log_warning(
                "Encerrado pelo usuário."
            )

            raise

        except Exception as erro:

            log_warning(
                f"ERRO FATAL "
                f"RECUPERADO: "
                f"{erro}"
            )

            log_warning(
                traceback.format_exc()
            )

            time.sleep(5)
