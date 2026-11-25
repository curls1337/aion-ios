# Aion for iOS (Native SwiftUI)

Aplikasi **native iOS (Swift 6 + SwiftUI)** untuk **AionUi** dengan desain **Warm Modern Bento (Konsep 3)**, **Adaptive Light & Obsidian Dark Mode**, dan **Apple Liquid Glass** (`GlassEffectContainer` + `.glassEffect` native iOS 26 dengan fallback specular glass mulus untuk iOS 17–18).

## Fitur Utama

- **Warm Modern Bento Dashboard**: Greeting dinamis, indikator status API real-time (`Aion API Online · 18ms`), kartu Bento 2×2 (*New Chat*, *Scheduled Tasks*, *Skills Library*, *Voice Mode*), serta *Recent Threads*.
- **Adaptive Light & Dark + Liquid Glass**: Otomatis mengikuti iOS atau ganti manual antara *Warm Light* (`#FAF8F5`) dan *Obsidian Dark* (`#121110`), lengkap dengan floating Liquid Glass navigation dock, composer bar, dan suggestion pills.
- **Fluid Editorial Chat**: Layout baca lega bergaya editorial, streaming respons real-time, kartu ringkasan (*Executive Summary*) + file chip, blok kode dengan tombol *Copy*, dan skill runner.
- **3 Mode Koneksi Backend**:
  1. **AionUi WebUI API & WebSocket (`:25808`)** — terhubung langsung ke host AionUi Anda via LAN atau Tailscale (`AionUi --webui --remote`).
  2. **OpenAI-Compatible SSE API** — mendukung `/v1/chat/completions` streaming.
  3. **Demo Mode (Bawaan)** — langsung bisa dicoba di iPhone begitu `.ipa` terpasang sebelum konfigurasi server.
- **Voice Mode Native**: Menggunakan Apple `Speech` & `AVAudioEngine` dengan orb Liquid Glass reaktif terhadap suara.
- **Zero External Dependencies**: 100% Apple native frameworks, cepat dikompilasi di GitHub Actions.

---

## Cara Build File `.ipa` di GitHub Actions

1. Buat repository baru di GitHub (misalnya `aion-ios`), lalu push seluruh folder ini:
   ```bash
   git remote add origin https://github.com/<USERNAME>/aion-ios.git
   git branch -M main
   git push -u origin main
   ```
2. Buka tab **Actions** di repository GitHub Anda → workflow **Build Aion iOS IPA** akan otomatis berjalan di runner **`macos-26` (Xcode 26 + iOS 26 SDK)**.
3. Setelah selesai (~2–3 menit), unduh artifact **`Aion-iOS-unsigned-ipa`** untuk mendapatkan **`Aion-iOS-unsigned.ipa`**.
4. Pasang `.ipa` di iPhone Anda menggunakan **SideStore**, **AltStore**, **TrollStore**, **Sideloadly**, atau **ESign**.

### Opsional: Signed `.ipa` dengan Apple Developer Certificate
Jika Anda ingin GitHub Actions juga menghasilkan `Aion-iOS-signed.ipa`, tambahkan GitHub Repository Secrets berikut:
- `P12_BASE64`: Sertifikat `.p12` dalam format base64
- `P12_PASSWORD`: Password sertifikat `.p12`
- `PROVISIONING_PROFILE_BASE64`: File `.mobileprovision` dalam format base64

Untuk otomatis menerbitkan GitHub Release berisi file `.ipa`, cukup push tag versi:
```bash
git tag v1.0.0 && git push origin v1.0.0
```

---

## Menghubungkan iPhone ke Server AionUi Anda

1. Jalankan AionUi dengan mode WebUI remote di komputer/server Anda:
   ```bash
   AionUi --webui --remote
   ```
2. Pastikan iPhone berada di jaringan **LAN yang sama** atau gunakan **Tailscale** agar bisa diakses dari mana saja.
3. Di aplikasi **Aion iOS**, buka tab **Settings → Aion API Connection**, pilih **AionUi WebUI API**, masukkan alamat `http://<IP-LAN-atau-Tailscale>:25808`, lalu ketuk **Test Connection**.
