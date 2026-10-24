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

## РћР±РЅРѕРІР»РµРЅРёРµ

РЈСЃС‚Р°РЅРѕРІРєР° СЃС‚Р°РІРёС‚ РїР°РЅРµР»СЊ С‡РµСЂРµР· `docker compose`, РґР°Р»СЊС€Рµ РѕР±РЅРѕРІР»РµРЅРёРµ вЂ” РѕРґРЅРѕР№ РєРѕРјР°РЅРґРѕР№:

~~~bash
cd /opt/awg-web-panel_3.1
docker compose pull && docker compose up -d
~~~

Р•СЃР»Рё РїРѕРјРµРЅСЏР» РєРѕРґ РІ СЂРµРїРѕР·РёС‚РѕСЂРёРё вЂ” РїСѓС€ РІ `main`, РґРѕР¶РґРёСЃСЊ СЃР±РѕСЂРєРё РѕР±СЂР°Р·Р° РІ GitHub Actions (~60 СЃРµРє), РїРѕС‚РѕРј `docker compose pull && docker compose up -d` РЅР° СЃРµСЂРІРµСЂРµ.

Р‘СЌРєР°Рї РєР»РёРµРЅС‚РѕРІ РїРµСЂРµРґ РѕР±РЅРѕРІР»РµРЅРёРµРј (РЅР° РІСЃСЏРєРёР№ СЃР»СѓС‡Р°Р№):

~~~bash
cp /opt/awg/clients.json /opt/awg/clients.json.before-$(date +%s)
~~~
