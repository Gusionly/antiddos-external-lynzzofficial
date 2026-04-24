# ptero-antiddos-tool

Installer anti-spam request ringan untuk **Pterodactyl Panel + Nginx**.

Tool ini **tidak menyentuh Wings**, **tidak mengubah Docker**, dan fokus hanya ke pembatasan request HTTP di Nginx supaya lebih aman untuk panel.

## Fitur

- Auto backup `nginx.conf` dan file site Pterodactyl
- Menambahkan `limit_req_zone` dan `limit_conn_zone` ke `nginx.conf`
- Menambahkan `limit_req` dan `limit_conn` ke file site Pterodactyl
- Validasi `nginx -t` sebelum reload
- Rollback otomatis kalau config baru gagal dites
- Uninstall mudah

## Yang diubah

### 1) `/etc/nginx/nginx.conf`
Ditambah block ini di dalam `http { ... }`:

```nginx
# BEGIN PTERO-ANTIDDOS MANAGED BLOCK
limit_req_zone $binary_remote_addr zone=ptero_req_limit:10m rate=15r/s;
limit_conn_zone $binary_remote_addr zone=ptero_conn_limit:10m;
# END PTERO-ANTIDDOS MANAGED BLOCK
```

### 2) File site Pterodactyl
Biasanya salah satu dari:

- `/etc/nginx/sites-available/pterodactyl.conf`
- `/etc/nginx/sites-enabled/pterodactyl.conf`
- `/etc/nginx/conf.d/pterodactyl.conf`

Ditambah block ini di dalam `server { ... }`:

```nginx
# BEGIN PTERO-ANTIDDOS MANAGED BLOCK
limit_req zone=ptero_req_limit burst=40 nodelay;
limit_conn ptero_conn_limit 40;
# END PTERO-ANTIDDOS MANAGED BLOCK
```

## Install cepat

### Opsi 1: clone repo

```bash
git clone https://github.com/USERNAME/ptero-antiddos-tool.git
cd ptero-antiddos-tool
sudo bash install.sh
```

### Opsi 2: custom site config

Kalau file site kamu bukan `pterodactyl.conf`:

```bash
sudo SITE_CONF=/etc/nginx/sites-available/panel.example.com.conf bash install.sh
```

## Kustom limit

Default:

- `RATE=15r/s`
- `BURST=40`
- `CONN=40`

Bisa diubah saat install:

```bash
sudo RATE=20r/s BURST=50 CONN=50 bash install.sh
```

## Uninstall

```bash
sudo bash uninstall.sh
```

## Catatan penting

- Tool ini untuk **proteksi dasar anti spam request**, bukan mitigasi DDoS besar skala L3/L4.
- Untuk serangan besar, tetap disarankan pakai **Cloudflare**, reverse proxy, atau proteksi upstream dari provider VPS.
- Tes dulu setelah install: login panel, buka dashboard, buka console server.

## Cocok untuk

- Ubuntu / Debian
- Nginx sebagai reverse proxy panel
- Pterodactyl Panel

## Tidak menyentuh

- Wings config
- Docker iptables
- Firewall game ports
