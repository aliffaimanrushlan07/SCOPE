# Running SCOPE — command reference

Quick copy-paste reference for VS Code's integrated terminal. For the full
build/setup guide, see `../SCOPE FYP/SCOPE-Build-Guide.md`.

Open a terminal in VS Code with **Terminal → New Terminal**, or **⌃\`**.

---

## Fastest path — backend + dashboard together

One command starts the database, backend and dashboard, and waits for each
to actually be ready before starting the next.

```bash
cd ~/Desktop/PROJECT/scope && ./dev.sh
```

**To stop:** press **Ctrl+C** in that same terminal. This stops the backend
and dashboard. The database is left running on purpose — see [Database](#database)
below for why, and how to stop it if you need to.

Skip to [Mobile app](#mobile-app) if that's what you're here for — `dev.sh`
does not touch Flutter.

---

## Database

```bash
cd ~/Desktop/PROJECT/scope/infra
colima start          # only if not already running — check with: colima status
docker compose up -d
```

**Check it's healthy:**
```bash
docker compose ps
```
Look for `scope-db` with status `Up ... (healthy)`.

**Stop it:**
```bash
cd ~/Desktop/PROJECT/scope/infra && docker compose down
```
This is safe — your data persists in the `pgdata` volume between restarts. Only
`docker compose down -v` (note the `-v`) deletes the data, and re-runs
`schema.sql`/`seed.sql` on next start.

---

## Backend (FastAPI)

**Run:**
```bash
cd ~/Desktop/PROJECT/scope/backend
source .venv/bin/activate
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```
Leave the terminal open — this runs in the foreground.

**Stop:** **Ctrl+C** in that terminal.

**Check it's up** (from any other terminal):
```bash
curl http://127.0.0.1:8000/health
```
Expect `{"status":"ok"}`. Interactive API docs: <http://127.0.0.1:8000/docs>

---

## Admin dashboard (React)

Requires the backend to be running first (see above).

**Run:**
```bash
cd ~/Desktop/PROJECT/scope/dashboard
npm run dev
```
Opens on <http://localhost:5173>. Leave the terminal open.

**Stop:** **Ctrl+C** in that terminal.

**Sign in with** (development only):

| Email | Password |
|---|---|
| `officer@ncsm.org.my` | `ScopeDev2026!` |
| `researcher@ncsm.org.my` | `ScopeDev2026!` |

---

## Mobile app (Flutter)

Requires the backend to be running first (see above) — the emulator reaches
it automatically at `10.0.2.2:8000`.

### Start the emulator

```bash
flutter emulators --launch scope_pixel5_api29
```
Wait about 10–15 seconds for it to boot before running the app.

**List available emulators** (if you forget the name):
```bash
flutter emulators
```

**Stop the emulator:**
- Close its window, **or**
```bash
adb emu kill
```

### Run the app

```bash
cd ~/Desktop/PROJECT/scope/mobile
flutter run
```

This opens Flutter's interactive console in the terminal:

| Key | Action |
|---|---|
| `r` | Hot reload (apply code changes instantly) |
| `R` | Hot restart (reset app state) |
| `q` | **Quit** — stops the app on the device |
| `p` | Toggle debug paint / widget inspector borders |

**Stop:** press **q** in that terminal, or **Ctrl+C**.

### Run on a physical Android phone over USB

1. Connect via USB, enable USB debugging on the phone
2. Confirm it's detected:
   ```bash
   flutter devices
   ```
3. Find your Mac's LAN IP (needed so the phone can reach the backend):
   ```bash
   ipconfig getifaddr en0
   ```
4. Run with that address:
   ```bash
   cd ~/Desktop/PROJECT/scope/mobile
   flutter run --dart-define=API_BASE_URL=http://<your-mac-ip>:8000
   ```

For the installed demo APK — which cannot be given a `--dart-define` — set the
address on the phone instead. See [Demo APK](#demo-apk) below.

### Run on the iPhone (presentation device)

Same as above, but Xcode must be able to sign the app to your device first
(see §5.6 of the build guide for one-time setup). Once signed:
```bash
cd ~/Desktop/PROJECT/scope/mobile
flutter run --dart-define=API_BASE_URL=http://<your-mac-ip>:8000
```
⚠️ Free Apple ID signing expires after 7 days — rebuild onto the phone within
a week of presenting.

---

## Demo APK

A standing release APK on your own Android phone, reaching the backend on this
Mac over a wireless hotspot. No cable, and no rebuild when the address changes.

### Build it

```bash
cd ~/Desktop/PROJECT/scope/mobile && flutter build apk --release
```

Takes about 2 minutes. Output:
`build/app/outputs/flutter-apk/app-release.apk` (~57 MB).

Copy it somewhere you can upload from:
```bash
cp ~/Desktop/PROJECT/scope/mobile/build/app/outputs/flutter-apk/app-release.apk ~/Desktop/PROJECT/scope-demo.apk
```

Signed with the **debug keystore** on purpose. The Google Maps Android key is
restricted by package name plus SHA-1 certificate fingerprint, so switching to
a new release keystore would blank out S06 and S11 until that new fingerprint
was registered in the Google Cloud console.

### Install it

Transfer `scope-demo.apk` to the phone (Drive, Telegram, AirDroid) and open it.
Android will ask permission the first time — "Install unknown apps" must be
allowed for whichever app you transferred with (Settings → Apps → Special
access → Install unknown apps).

The phone must be **Android 10 or newer** (`minSdk = 29`).

### Network: the iPhone hotspot path

Both the MacBook and the Android phone join the **iPhone's** Personal Hotspot.
Both then keep internet access, which matters because S06 and S11 fetch Google
Maps tiles and render blank without it.

1. iPhone: Settings → Personal Hotspot → on. **Leave this screen open** — iOS
   switches the hotspot off when nothing is connected to it.
2. MacBook: join the hotspot. Android phone: join the same hotspot.
3. MacBook — find the address the hotspot gave it:
   ```bash
   ipconfig getifaddr en0
   ```
   It will be `172.20.10.x`. iOS pins this network to `172.20.10.0/28`, so the
   Mac is always somewhere between `.2` and `.14`.
4. MacBook — start everything:
   ```bash
   cd ~/Desktop/PROJECT/scope && ./dev.sh
   ```
5. Android — open SCOPE → **About SCOPE** (via the SCOPE logo at the top) →
   **Connection settings**. Type the address from step 3, tap **Test
   connection**, then **Save**.

   Typing just `172.20.10.4` is enough — `http://` and `:8000` are filled in.

The address is remembered between launches, so step 5 is only needed when DHCP
hands the Mac a different one.

**Test connection** is the diagnostic worth using before you present: it tells
you whether the address is reachable at all, separating a mistyped IP from a
backend that isn't running.

### Fallback if the wireless path fails

USB cable, no network at all:
```bash
adb reverse tcp:8000 tcp:8000
```
Then set the address in the app to `http://127.0.0.1:8000`. This is already
permitted by the app's cleartext policy.

---

## Everything at once — typical session

```bash
# Terminal 1
cd ~/Desktop/PROJECT/scope && ./dev.sh

# Terminal 2 (after Terminal 1 says "SCOPE is running")
flutter emulators --launch scope_pixel5_api29
cd ~/Desktop/PROJECT/scope/mobile && flutter run
```

**To stop everything:** `q` in Terminal 2, then **Ctrl+C** in Terminal 1.

---

## If something won't start

| Symptom | Likely cause | Fix |
|---|---|---|
| `dev.sh` exits immediately, mentions `.venv` | Backend virtualenv missing | `cd backend && python3.11 -m venv .venv && ./.venv/bin/pip install -r requirements.txt` |
| `dev.sh` exits immediately, mentions `node_modules` | Dashboard deps missing | `cd dashboard && npm install` |
| `curl http://127.0.0.1:8000/health` hangs or refuses | Backend not actually running | Check the backend terminal for an error |
| Dashboard loads but every request fails / CORS error | Backend not running, or wrong origin | Confirm backend is up; check `DASHBOARD_ORIGIN` in `backend/.env` matches `http://localhost:5173` |
| `flutter run` can't reach the backend | Wrong base URL for the target device | Emulator needs no flag; a physical device needs `--dart-define=API_BASE_URL=http://<mac-ip>:8000` |
| Emulator camera hangs on a spinner | AVD set to `webcam0` instead of `emulated` | See `SCOPE-Build-Guide.md` — switch `hw.camera.back` in the AVD config |
| Port 8000 or 5173 already in use | A previous run wasn't stopped cleanly | `lsof -iTCP:8000 -sTCP:LISTEN` (or `:5173`) to find the PID, then `kill <pid>` |

### Demo APK on the hotspot

| Symptom | Likely cause | Fix |
|---|---|---|
| **Test connection** says no response | Wrong address, or the backend isn't running | Re-check `ipconfig getifaddr en0` on the Mac; confirm `curl http://127.0.0.1:8000/health` answers there |
| Every request fails but Test connection passed | The Mac moved to a different network after you saved | Re-run step 3 and re-save the address |
| App reaches the backend, but S06/S11 maps are blank | No internet on the phone, or the Maps key restriction | Confirm the iPhone hotspot has mobile data; confirm the debug SHA-1 is still registered for the Maps key |
| Requests fail only in the release APK, never in `flutter run` | The Mac's address is outside the cleartext allowlist | Add it to `mobile/android/app/src/main/res/xml/network_security_config.xml` and rebuild — Android blocks cleartext to unlisted hosts |
| Hotspot drops when you stop looking at the iPhone | iOS switches Personal Hotspot off when no client is attached | Keep the Personal Hotspot settings screen open until both devices have joined |
| Report submission returns "You have submitted several reports recently" | Per-device hourly rate limit | `RATE_LIMIT_PER_DEVICE_PER_HOUR` in `backend/.env` — raised to 50 for demos, designed value is 5 |
