<!--
  title: SQL Server Dockerized Backup Script
  description: Cari programmer profesional di Cilegon? Saya menawarkan layanan pengembangan web, aplikasi, dan solusi IT terpercaya.
  author: kurob
  url: https://okuru.id
  keywords: backup SQL Server, Docker, Bash script, database backup, programmer Cilegon, web developer Cilegon, okuru.id
-->

# 🛡️ SQL Server Dockerized Backup Script

Backup tool for Microsoft SQL Server running inside Docker containers.  
Supports interactive selection, authentication, and automatic `.bak` file creation in container or host path.

---
## 🇬🇧 English

### 📦 Features
- Automatically detects running SQL Server containers using the official Microsoft image.
- Interactive container selection (by name or index).
- Authenticates using the `SA` account.
- Dumps a selected database to a `.bak` file inside the container or exported volume.
- Works on both dev & prod environments.

### 🚀 How to Use

1. **Run the script:**
   ```bash
   ./backup-db.sh
   ```

2. **Follow the prompts:**
   - Select the running container.
   - Enter the `SA` password.
   - Choose the database to back up.
   - Define the output location.

3. **Example backup output:**
   ```
   /var/opt/mssql/backup/my_database_20250616_0830.bak
   ```

### ⚙️ Requirements
- Docker installed on host.
- SQL Server container running.
- `sqlcmd` CLI tool available inside the container (varies by image tag).

---

## 🇮🇩 Bahasa Indonesia

### 📦 Fitur
- Deteksi otomatis container Docker dengan image SQL Server resmi.
- Seleksi container secara interaktif (berdasarkan nama atau nomor).
- Autentikasi menggunakan `SA` user.
- Backup database ke file `.bak` di direktori tujuan.
- Bisa dijalankan di server pengembangan atau produksi.

### 🚀 Cara Pakai

1. **Jalankan script:**
   ```bash
   ./backup-db.sh
   ```

2. **Ikuti prompt:**
   - Pilih container yang aktif.
   - Masukkan password `SA`.
   - Pilih database yang ingin dibackup.
   - Tentukan lokasi penyimpanan hasil backup.

3. **Contoh hasil backup:**
   ```
   /var/opt/mssql/backup/my_database_20250616_0830.bak
   ```

### ⚙️ Persyaratan
- Docker sudah terinstal.
- Container SQL Server aktif.
- Tools `sqlcmd` tersedia di dalam container (bisa beda versi image!).

---

## 📁 Struktur Direktori

```
.
├── backup-db.sh      # Main script
├── backups/          # (Optional) Output .bak files
└── README.md
```

---

## 📝 Catatan Tambahan

- Image `:2019-latest` yang lebih baru kadang **tidak menyertakan `sqlcmd`**.
  - ✅ Gunakan image seperti `mcr.microsoft.com/mssql/server:2019-CU18-ubuntu-20.04` untuk memastikan tools tersedia.
  - 🔧 Atau mount tools dari host atau container lain jika diperlukan.

---

## 🧑‍💻 Kontribusi

Pull requests and feedback are welcome. This is a simple script intended to help devs manage Dockerized SQL Server backups more easily.
