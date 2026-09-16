# KNXBridge Releases

Dieses Repository enthält öffentliche Debian-Release-Pakete und den Installer für KNX Bridge.

KNX Bridge verbindet EVCC-Datenpunkte mit KNX/IP-Gruppenadressen. Die App bietet eine Weboberfläche für Gateway-Konfiguration, Datenpunktsuche, Mappings und Statusdiagnose.

## Installation und Update

```bash
curl -fsSL https://raw.githubusercontent.com/ehive-dev/KNXBridge_releases/main/install.sh | sudo bash
```

Eine bestimmte Version installieren:

```bash
curl -fsSL https://raw.githubusercontent.com/ehive-dev/KNXBridge_releases/main/install.sh | sudo bash -s -- --tag v0.1.1
```

## Service

```bash
systemctl status knx-bridge --no-pager
journalctl -u knx-bridge -f
```

Die Weboberfläche läuft standardmäßig auf Port `3032`. Der lokale Health-Check lautet:

```bash
curl http://127.0.0.1:3032/healthz
```

Die KNX- und EVCC-Konfiguration bleibt bei Aktualisierungen unter `/etc/knx-bridge/config.yaml` erhalten.
