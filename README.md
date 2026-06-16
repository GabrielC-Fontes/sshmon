# SSHMON

SSHMON e um monitor de disponibilidade via SSH para servidores Linux. Ele testa periodicamente a conexao com os hosts configurados, registra logs separados por tipo de evento e envia alertas por e-mail e/ou Telegram quando um host fica offline ou volta a responder.

## Recursos

- Monitoramento de varios hosts em paralelo.
- Autenticacao por senha ou chave privada SSH.
- Alertas SMTP para hosts offline e recuperados.
- Alertas Telegram via bot criado no BotFather.
- Supressao de alertas repetidos pelo mesmo host/tipo por 24 horas.
- Logs separados para sucesso, falha, acesso negado e avisos.
- Rotacao simples de logs por tamanho.
- Recarregamento automatico do `hosts.json` quando o arquivo e alterado.
- Instalador com criacao de servico `systemd`.

## Requisitos

- Linux com `systemd`.
- Python 3.
- Cliente OpenSSH (`ssh`).
- Acesso `sudo` para instalacao.
- Conta SMTP para envio de alertas.

Dependencias Python:

```txt
paramiko==4.0.0
python-dotenv==1.1.1
cryptography==45.0.7
```

## Instalacao

Clone ou copie os arquivos do projeto para o servidor e execute:

```bash
chmod +x install.sh
./install.sh
```

O instalador ira:

- validar os arquivos obrigatorios;
- validar Python, `venv`, `pip` e cliente SSH;
- configurar SMTP e criar o arquivo `.env`;
- configurar Telegram opcionalmente;
- criar o usuario de servico `sshmon`;
- copiar os arquivos para `/opt/sshmon`;
- criptografar a senha SMTP em `/etc/sshmon`;
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
    "certificado": "/home/sshmon/.ssh/servidor2.pem"
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
SMTP_PASS_ENC_FILE="/etc/sshmon/smtp_pass.enc"
SMTP_PASS_KEY_FILE="/etc/sshmon/smtp_pass.key"
SMTP_TO="destino@exemplo.com"
TELEGRAM_BOT_TOKEN=""
TELEGRAM_CHAT_ID=""
INTERVALO_VERIFICACAO="5"
FALHAS_PARA_ALERTA="3"
ALERTA_EMAIL_INTERVALO_HORAS="24"
SSH_TIMEOUT="5"
MAX_LOG_SIZE_MB="10"
```

`SMTP_TLS` aceita `starttls` ou `ssl`.

`INTERVALO_VERIFICACAO` e `SSH_TIMEOUT` sao em segundos.

`ALERTA_EMAIL_INTERVALO_HORAS` controla por quantas horas um alerta do mesmo tipo para o mesmo host nao sera reenviado. O padrao e `24`.

## Alertas Telegram

Para habilitar alertas via Telegram:

1. Abra uma conversa com `@BotFather` no Telegram.
2. Envie `/newbot` e siga as instrucoes para criar o bot.
3. Copie o token gerado pelo BotFather.
4. Abra uma conversa com o bot criado e envie `/start`.
5. Acesse no navegador:

```text
https://api.telegram.org/botSEU_TOKEN/getUpdates
```

6. Procure o campo `chat.id` no retorno e use esse valor como `TELEGRAM_CHAT_ID`.

Para grupos, adicione o bot ao grupo, envie uma mensagem no grupo e consulte o mesmo `getUpdates`. O `chat.id` de grupos normalmente e negativo.

Durante a instalacao, depois que o token for informado, o instalador mostra a URL de `getUpdates` ja preenchida com o token e tambem tenta buscar o `chat_id` automaticamente. Se ele nao encontrar, abra a URL no navegador, procure por `"chat":{"id":...}` e informe esse numero quando solicitado.

O `/start` nao precisa ser enviado sempre. Em conversa privada, o `chat_id` normalmente permanece o mesmo. Envie `/start` novamente se o bot foi bloqueado/desbloqueado, se a conversa foi recriada ou se o teste de envio falhar. Em grupos, o `chat_id` pode mudar se o grupo for migrado para supergrupo; nesse caso, consulte `getUpdates` novamente e atualize `TELEGRAM_CHAT_ID`.

Depois edite:

```bash
sudo nano /opt/sshmon/.env
```

E configure:

```env
TELEGRAM_BOT_TOKEN="123456789:token_do_bot"
TELEGRAM_CHAT_ID="123456789"
```

Reinicie o servico:

```bash
sudo systemctl restart sshmon
```

Se SMTP e Telegram estiverem configurados, o SSHMON tentara enviar os alertas pelos dois canais. Se apenas um estiver configurado corretamente, esse canal sera usado.

## Logs

Os logs ficam em `/var/log/sshmon`:

```bash
successful.log
unsuccessful.log
accessdenied.log
warnings.log
alert_state.json
```

`alert_state.json` guarda o horario dos ultimos alertas enviados para evitar reenvios repetidos dentro da janela configurada.

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
- A senha SMTP fica fora do `.env`, criptografada em `/etc/sshmon/smtp_pass.enc`.
- A chave local de descriptografia fica em `/etc/sshmon/smtp_pass.key`.
- Os arquivos devem ficar com permissao restrita:

```bash
sudo chown root:sshmon /etc/sshmon/smtp_pass.enc /etc/sshmon/smtp_pass.key
sudo chmod 640 /etc/sshmon/smtp_pass.enc /etc/sshmon/smtp_pass.key
```

- A criptografia protege a senha em repouso, mas nao impede acesso por `root` nem por alguem que comprometa o usuario de servico `sshmon`, pois o servico precisa descriptografar a senha automaticamente ao iniciar.

- Prefira chave SSH quando possivel.
- Coloque chaves `.pem` ou `.ppk` em `/home/sshmon/.ssh/`.
- Restrinja permissoes das chaves privadas:

```bash
sudo chown sshmon:sshmon /home/sshmon/.ssh/*.pem /home/sshmon/.ssh/*.ppk
sudo chmod 600 /home/sshmon/.ssh/*.pem /home/sshmon/.ssh/*.ppk
```

## Licenca

Este projeto esta licenciado sob a MIT License. Voce pode usar, copiar, modificar, distribuir e utilizar este software para qualquer finalidade, inclusive comercial, desde que mantenha o aviso de copyright e a licenca.

O repositorio oficial e mantido apenas pelo autor. Contribuicoes podem ser sugeridas via Pull Request, mas alteracoes no repositorio dependem de aprovacao do mantenedor.
