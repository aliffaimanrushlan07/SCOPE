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

### Run on a physical Android phone instead

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
