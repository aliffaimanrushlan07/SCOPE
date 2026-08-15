#!/usr/bin/env bash
#
# SCOPE — one-command dev startup.
#
# Starts the database, backend and dashboard together, and stops the backend
# and dashboard cleanly when you press Ctrl+C in this terminal.
#
# Usage (from the repo root, in a VS Code terminal or any terminal):
#   ./dev.sh
#
# The database is left running afterwards — it's cheap to leave up and other
# tools (psql, the constraint tests) expect it. Stop it explicitly with:
#   cd infra && docker compose down

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="$ROOT/.devlogs"
mkdir -p "$LOG_DIR"

# --- Preflight: fail early with a clear message rather than half-starting ---

if [ ! -f "$ROOT/backend/.venv/bin/activate" ]; then
  echo "Backend virtualenv not found at backend/.venv"
  echo "Run:  cd backend && python3.11 -m venv .venv && ./.venv/bin/pip install -r requirements.txt"
  exit 1
fi

if [ ! -d "$ROOT/dashboard/node_modules" ]; then
  echo "Dashboard dependencies not installed."
  echo "Run:  cd dashboard && npm install"
  exit 1
fi

# --- Database ---------------------------------------------------------------

echo "==> Database"
if ! colima status >/dev/null 2>&1; then
  colima start
fi
( cd "$ROOT/infra" && docker compose up -d )

echo "==> Waiting for the database to report healthy..."
for _ in $(seq 1 30); do
  health="$(docker inspect --format '{{.State.Health.Status}}' scope-db 2>/dev/null)"
  [ "$health" = "healthy" ] && break
  sleep 1
done
if [ "$health" != "healthy" ]; then
  echo "Database did not become healthy in time. Check: docker compose logs -f (in infra/)"
  exit 1
fi

# --- Backend -----------------------------------------------------------------
# `exec` replaces the subshell with uvicorn itself, so the PID captured below
# is uvicorn's own PID and `kill` on it is not killing an intermediate wrapper.

echo "==> Backend"
( cd "$ROOT/backend" && source .venv/bin/activate && \
  exec uvicorn app.main:app --reload --host 0.0.0.0 --port 8000 \
) > "$LOG_DIR/backend.log" 2>&1 &
BACKEND_PID=$!

echo "==> Waiting for the backend to respond..."
for _ in $(seq 1 30); do
  curl -sf http://127.0.0.1:8000/health >/dev/null 2>&1 && break
  sleep 1
done
if ! curl -sf http://127.0.0.1:8000/health >/dev/null 2>&1; then
  echo "Backend did not come up. Last lines of $LOG_DIR/backend.log:"
  tail -n 20 "$LOG_DIR/backend.log"
  kill "$BACKEND_PID" 2>/dev/null
  exit 1
fi

# --- Dashboard -----------------------------------------------------------------
# Calls the vite binary directly (not `npm run dev`) for the same reason: npm
# spawns vite as a child process it does not always forward signals to, which
# leaves an orphaned dev server behind after Ctrl+C.

echo "==> Dashboard"
( cd "$ROOT/dashboard" && exec ./node_modules/.bin/vite ) \
  > "$LOG_DIR/dashboard.log" 2>&1 &
DASHBOARD_PID=$!

# --- Clean shutdown on Ctrl+C -------------------------------------------------

CLEANED_UP=0
cleanup() {
  [ "$CLEANED_UP" = "1" ] && return
  CLEANED_UP=1
  echo ""
  echo "==> Stopping backend and dashboard..."
  kill "$BACKEND_PID" "$DASHBOARD_PID" 2>/dev/null
  wait "$BACKEND_PID" "$DASHBOARD_PID" 2>/dev/null
  echo "==> Database left running. Stop it with: cd infra && docker compose down"
}
trap cleanup EXIT INT TERM

echo ""
echo "================================================================"
echo " SCOPE is running"
echo "   Backend    http://127.0.0.1:8000/docs"
echo "   Dashboard  http://localhost:5173"
echo "   Logs       $LOG_DIR/backend.log"
echo "              $LOG_DIR/dashboard.log"
echo ""
echo " Press Ctrl+C to stop the backend and dashboard."
echo "================================================================"

wait
