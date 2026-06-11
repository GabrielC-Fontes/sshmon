# SSHMON

SSHMON e um monitor de disponibilidade via SSH para servidores Linux. Ele testa periodicamente a conexao com os hosts configurados, registra logs separados por tipo de evento e envia alertas por e-mail quando um host fica offline ou volta a responder.

## Recursos

- Monitoramento de varios hosts em paralelo.
- Autenticacao por senha ou chave privada SSH.
- Alertas SMTP para hosts offline e recuperados.
- Logs separados para sucesso, falha, acesso negado e avisos.
- Rotacao simples de logs por tamanho.
- Recarregamento automatico do `hosts.json` quando o arquivo e alterado.
- Instalador com criacao de servico `systemd`.

## Requisitos

- Linux com `systemd`.
- Python 3.
- Acesso `sudo` para instalacao.
- Conta SMTP para envio de alertas.

Dependencias Python:

```txt
paramiko==4.0.0
python-dotenv==1.1.1
```

## Instalacao

Clone ou copie os arquivos do projeto para o servidor e execute:

```bash
chmod +x install.sh
./install.sh
```

O instalador ira:

- validar os arquivos obrigatorios;
- configurar SMTP e criar o arquivo `.env`;
- criar o usuario de servico `sshmon`;
- copiar os arquivos para `/opt/sshmon`;
- criar os logs em `/var/log/sshmon`;
- criar ambiente virtual Python;
- instalar as dependencias;
- criar e iniciar o servico `sshmon`.

## Configuracao dos Hosts

Edite o arquivo:

```bash
sudo nano /opt/sshmon/hosts.json
```

Exemplo com senha:

```json
{
    "nome": "Servidor 1",
    "ip": "192.168.1.10",
    "usuario": "usuario",
    "senha": "senha"
}
```

Exemplo com chave SSH:

```json
{
    "nome": "Servidor 2",
    "ip": "192.168.1.20",
    "usuario": "usuario",
    "certificado": "/home/sshmon/.ssh/id_rsa"
}
```

Cada host precisa ter `ip`, `usuario` e pelo menos um metodo de autenticacao: `senha` ou `certificado`.

## Variaveis de Ambiente

O arquivo `.env` fica em:

```bash
/opt/sshmon/.env
```

Variaveis disponiveis:

```env
SMTP_SERVER="smtp.exemplo.com"
SMTP_PORT="587"
SMTP_TLS="starttls"
SMTP_USER="alertas@exemplo.com"
SMTP_PASS="senha"
SMTP_TO="destino@exemplo.com"
INTERVALO_VERIFICACAO="5"
FALHAS_PARA_ALERTA="3"
SSH_TIMEOUT="5"
MAX_LOG_SIZE_MB="10"
```

`SMTP_TLS` aceita `starttls` ou `ssl`.

## Logs

Os logs ficam em `/var/log/sshmon`:

```bash
successful.log
unsuccessful.log
accessdenied.log
warnings.log
```

## Comandos Uteis

Ver status do servico:

```bash
sudo systemctl status sshmon
```

Reiniciar:

```bash
sudo systemctl restart sshmon
```

Acompanhar logs do systemd:

```bash
sudo journalctl -u sshmon -f
```

Acompanhar logs do SSHMON:

```bash
tail -f /var/log/sshmon/warnings.log
tail -f /var/log/sshmon/unsuccessful.log
tail -f /var/log/sshmon/accessdenied.log
tail -f /var/log/sshmon/successful.log
```

## Desinstalacao

```bash
chmod +x uninstall.sh
./uninstall.sh
```

## Seguranca

- Nao publique o arquivo `.env`.
- Prefira chave SSH quando possivel.
- Restrinja permissoes da chave privada:

```bash
sudo chown sshmon:sshmon /home/sshmon/.ssh/id_rsa
sudo chmod 600 /home/sshmon/.ssh/id_rsa
```

## Licenca

Este projeto esta licenciado sob a MIT License. Voce pode usar, copiar, modificar, distribuir e utilizar este software para qualquer finalidade, inclusive comercial, desde que mantenha o aviso de copyright e a licenca.

O repositorio oficial e mantido apenas pelo autor. Contribuicoes podem ser sugeridas via Pull Request, mas alteracoes no repositorio dependem de aprovacao do mantenedor.
