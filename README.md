# SCOPE

**AI-Assisted Smoking Violation Reporting and Monitoring System**
Final Year Project · Bachelor of Information Technology (Hons) in Computer Application Development

A mobile application allowing members of the public to anonymously report smoking violations in gazetted non-smoking premises, and a web dashboard giving enforcement officers and NCSM staff hotspot maps, temporal analytics and exportable report data.

Photographic evidence is classified by a fine-tuned Vision Transformer **before** submission. Administrators hold read-only access — no report changes state after it is filed.

---

## Repository layout

| Path | Contents |
|---|---|
| `infra/` | Docker Compose, database schema, seed and verification SQL |
| `backend/` | FastAPI — report API, admin API, classification endpoint |
| `mobile/` | Flutter application (screens S01–S15) |
| `dashboard/` | React + Leaflet admin dashboard (screens D01–D06) |
| `ml/` | Dataset, training notebooks, exported model artefacts |
| `docs/` | Postman collection, test case records |

Design documentation lives in `../SCOPE FYP/`:
`SCOPE-Build-Guide.md`, `SCOPE-System-Flow-Revised.md`, and `Misc/files/` (ERD, Data Dictionary, DFD, Swimlane).

---

## Stack

Per Table 3.5 of the final report.

| Layer | Technology |
|---|---|
| Mobile | Flutter (Dart) · Android Studio |
| Backend | Python 3.11 + FastAPI |
| Database | PostgreSQL 15 + PostGIS 3.4 |
| AI / ML | TensorFlow + Keras · fine-tuned Vision Transformer, served server-side |
| Dashboard | React.js + Leaflet.js |
| Mapping | Google Maps (mobile) · Leaflet/OSM (dashboard) |

---

## Getting started

### 1. Database

```bash
cd infra && docker compose up -d
```

Verify the schema:

```bash
docker exec -i scope-db psql -U scope -d scope -f - < infra/verify.sql
```

Six tables, PostGIS active, two infographic slots and two admin accounts.

The SQL in `infra/` runs **only on first boot**, when the volume is empty. After editing `schema.sql` or `seed.sql`:

```bash
cd infra && docker compose down -v && docker compose up -d
```

Development credentials — never deploy these:

| Email | Password | Role |
|---|---|---|
| `officer@ncsm.org.my` | `ScopeDev2026!` | OFFICER |
| `researcher@ncsm.org.my` | `ScopeDev2026!` | RESEARCHER |

### 2. Backend

```bash
cd backend && cp .env.example .env
```

Generate a JWT secret into `.env`, then run:

```bash
cd backend && ./.venv/bin/python -m uvicorn app.main:app --reload
```

Interactive API documentation: <http://127.0.0.1:8000/docs>

**Postman.** Import `docs/scope-openapi.json` — Postman builds the full
collection from the OpenAPI schema, so it never drifts from the code. Re-export
after changing any route:

```bash
cd backend && ./.venv/bin/python -c "import json; from app.main import app; json.dump(app.openapi(), open('../docs/scope-openapi.json','w'), indent=2)"
```

### 3. Admin dashboard

```bash
cd dashboard && cp .env.example .env && npm install
```

```bash
cd dashboard && npm run dev
```

Opens on <http://localhost:5173>. The backend must be running, and its
`DASHBOARD_ORIGIN` must match that URL or CORS will block every request.

### 4. End-to-end check

With the database and API running:

```bash
./backend/.venv/bin/python docs/e2e_check.py
```

52 assertions covering the full reporting path (S10 → S13 → S14) and the
administrative path (D01 → D05), including the design rules below.

---

## Design constraints enforced in code

These are not implementation details — each one is a decision defended in the project documentation. Do not "fix" them.

- **No report status anywhere.** No `status`, `verified_by`, `verified_at` or `reviewed_by` column, no status badge on S14, no status filter on D04. Evidence is validated pre-submission and administrators are read-only, so nothing can change a report after filing.
- **No reporter entity.** Anonymity is achieved by not collecting identity. `device_id` is generated on the handset and resolves to no person.
- **Maximum three photographs per report**, enforced by a database constraint, not only by the UI.
- **Only `PASS` classifications persist.** A total failure returns the reporter to S08 and creates no report.
- **The public map (S06) shows density, never pins.** Individual pins would publicly attribute a report to a named premise.
- **Two fixed infographic slots.** D06 can replace or delete (empty) each slot, but the slot rows themselves cannot be added or removed; S04 lists published slots only.
- **No violation type, no premise type.** The reporter supplies an optional free-text `premise_name` only.
