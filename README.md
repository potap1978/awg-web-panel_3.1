## Установка

### Требования

- Ubuntu 24.04 / Debian 12
- Root (или sudo)
- Публичный IPv4
- Порт 80/tcp открыт (для Let's Encrypt)

### Шаги

```bash
git clone https://github.com/potap1978/awg-web-panel_3.1.git /opt/awg-web-panel_3.1
cd /opt/awg-web-panel_3.1
sudo bash install.sh
```

## Обновление

Установка ставит панель через `docker compose`, дальше обновление — одной командой:

~~~bash
cd /opt/awg-web-panel_3.1
docker compose pull && docker compose up -d
~~~

Бэкап клиентов перед обновлением (на всякий случай):

~~~bash
cp /opt/awg/clients.json /opt/awg/clients.json.before-$(date +%s)
~~~
