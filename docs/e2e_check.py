"""End-to-end check of the SCOPE API.

Drives the full reporting path (S08 -> S13 -> S14) and the full administrative
path (D01 -> D05), then asserts the design rules that Chapter 4 claims:

  - a report whose evidence fails validation cannot be created
  - a duplicate submit returns the original reference, not a second report
  - the public heatmap exposes no report identity
  - no endpoint exists that alters a filed report

Usage:
    python docs/e2e_check.py [base_url]
"""

from __future__ import annotations

import csv
import io
import pathlib
import sys
import uuid

import httpx
from PIL import Image

BASE = sys.argv[1] if len(sys.argv) > 1 else "http://127.0.0.1:8000"
ADMIN_EMAIL = "officer@ncsm.org.my"
ADMIN_PASSWORD = "ScopeDev2026!"

passed = 0
failed = 0


def check(label: str, condition: bool, detail: str = "") -> None:
    global passed, failed
    if condition:
        passed += 1
        print(f"  PASS  {label}")
    else:
        failed += 1
        print(f"  FAIL  {label}  {detail}")


def make_image(seed: int, colour: tuple[int, int, int]) -> bytes:
    """Deterministic image bytes. The stub classifier scores by content hash,
    so a given seed always yields the same confidence."""
    img = Image.new("RGB", (64, 64), colour)
    for x in range(seed % 32):
        img.putpixel((x, x), (0, 0, 0))
    buf = io.BytesIO()
    img.save(buf, format="JPEG")
    return buf.getvalue()


def dataset_images(label: str, count: int) -> list[bytes] | None:
    """Real photographs from the held-out test split, if the dataset is present.

    Preferred over synthetic images once a trained model is wired in: a genuine
    cigarette detector correctly REJECTS procedurally generated noise, so the
    seed search below can never satisfy passed=True against a real model. Using
    real images tests the same API contract without depending on the classifier
    misbehaving.
    """
    manifest = pathlib.Path(__file__).resolve().parents[1] / "ml" / "data" / "manifest.csv"
    if not manifest.exists():
        return None

    ml_dir = manifest.parent.parent
    chosen: list[bytes] = []
    with manifest.open() as handle:
        for row in csv.DictReader(handle):
            if row["split"] != "test" or row["label"] != label:
                continue
            path = ml_dir / row["path"]
            if path.exists():
                chosen.append(path.read_bytes())
                if len(chosen) == count:
                    return chosen
    return chosen or None


def find_images(target_pass: bool, count: int) -> list[bytes]:
    """Images the classifier scores the way this test needs.

    Uses real dataset photographs when available, and falls back to a search
    over synthetic images so the suite still runs on a machine that has the
    code but not the 450 MB image corpus.
    """
    real = dataset_images("smoking" if target_pass else "notsmoking", count)
    if real and len(real) == count:
        return real

    found: list[bytes] = []
    for seed in range(500):
        data = make_image(seed, (seed % 256, 100, 150))
        response = httpx.post(
            f"{BASE}/api/v1/classify",
            files=[("photos", (f"p{seed}.jpg", data, "image/jpeg"))],
            timeout=30,
        )
        if response.status_code != 200:
            continue
        if response.json()["photos"][0]["passed"] is target_pass:
            found.append(data)
            if len(found) == count:
                return found

    raise RuntimeError(
        f"Could not find {count} images with passed={target_pass}.\n"
        "With a real model wired in this is expected for passed=True — synthetic "
        "noise should never look like a cigarette. Provide the dataset "
        "(ml/data/manifest.csv) or set AI_STUB_MODE=true to run this suite."
    )


print(f"\nSCOPE API end-to-end check -> {BASE}\n")

# ---------------------------------------------------------------------------
print("S10 — AI photo evidence validation")
# ---------------------------------------------------------------------------
passing_images = find_images(True, 2)
failing_images = find_images(False, 1)

files = [
    ("photos", ("a.jpg", passing_images[0], "image/jpeg")),
    ("photos", ("b.jpg", failing_images[0], "image/jpeg")),
    ("photos", ("c.jpg", passing_images[1], "image/jpeg")),
]
r = httpx.post(f"{BASE}/api/v1/classify", files=files, timeout=30)
check("classify accepts 3 photographs", r.status_code == 200, r.text[:200])
verdict = r.json()

check("outcome is PASS when >=1 photo clears", verdict["outcome"] == "PASS")
check("evaluated 3 photographs", verdict["photos_evaluated"] == 3)
check("passed 2 of 3", verdict["photos_passed"] == 2)
check("failing photo carries an actionable reason",
      any(p["reason"] for p in verdict["photos"] if not p["passed"]))
check("threshold is reported to the client", "threshold_used" in verdict)
check("validation token issued", len(verdict["validation_token"]) == 32)

r = httpx.post(
    f"{BASE}/api/v1/classify",
    files=[("photos", (f"{i}.jpg", make_image(i, (i, 0, 0)), "image/jpeg")) for i in range(4)],
    timeout=30,
)
check("4 photographs rejected (three-photo maximum)", r.status_code == 400, r.text[:120])

# ---------------------------------------------------------------------------
print("\nS12/S13 — report submission")
# ---------------------------------------------------------------------------
device_id = f"e2e-{uuid.uuid4().hex[:16]}"
payload = {
    "validation_token": verdict["validation_token"],
    "device_id": device_id,
    "latitude": 3.146600,
    "longitude": 101.711300,
    "premise_name": "E2E Test Food Court",
    "address_text": "Jalan Bukit Bintang, Kuala Lumpur",
    "capture_latitude": 3.146590,
    "capture_longitude": 101.711280,
    "reported_at": "2026-08-13T10:30:00+00:00",
}
r = httpx.post(f"{BASE}/api/v1/reports", json=payload, timeout=30)
check("report created", r.status_code == 201, r.text[:200])
created = r.json()
reference_no = created["reference_no"]

check("reference number issued", reference_no.startswith("SCP-"))
check("only passing photographs stored (2, not 3)", created["photos_stored"] == 2,
      f"got {created['photos_stored']}")
check("reference excludes ambiguous characters I O 0 1",
      not set("IO01") & set(reference_no.split("-")[-1]))

# Duplicate submit — section 7
r2 = httpx.post(f"{BASE}/api/v1/reports", json=payload, timeout=30)
check("duplicate submit returns 201, not an error", r2.status_code == 201, r2.text[:120])
check("duplicate submit flagged as duplicate", r2.json()["duplicate_submission"] is True)
check("duplicate submit returns the SAME reference",
      r2.json()["reference_no"] == reference_no)

# Client cannot invent a validation token
r = httpx.post(
    f"{BASE}/api/v1/reports",
    json={**payload, "validation_token": "f" * 32},
    timeout=30,
)
check("unknown validation token rejected", r.status_code == 400, r.text[:120])

# A total failure cannot be submitted
r = httpx.post(
    f"{BASE}/api/v1/classify",
    files=[("photos", ("fail.jpg", failing_images[0], "image/jpeg"))],
    timeout=30,
)
fail_verdict = r.json()
check("single failing photo yields FAIL", fail_verdict["outcome"] == "FAIL")
r = httpx.post(
    f"{BASE}/api/v1/reports",
    json={**payload, "validation_token": fail_verdict["validation_token"]},
    timeout=30,
)
check("FAILED evidence cannot be submitted", r.status_code == 409, r.text[:120])

# ---------------------------------------------------------------------------
print("\nS14 — report history (device-bound)")
# ---------------------------------------------------------------------------
r = httpx.get(f"{BASE}/api/v1/reports/device/{device_id}", timeout=30)
check("history returns the device's reports", r.status_code == 200 and len(r.json()) == 1)
item = r.json()[0]
check("history row carries NO status field", "status" not in item, str(item.keys()))
check("history row carries a thumbnail", item["thumbnail_path"] is not None)

r = httpx.get(f"{BASE}/api/v1/reports/device/other-device-entirely", timeout=30)
check("another device sees nothing", r.status_code == 200 and r.json() == [])

r = httpx.get(f"{BASE}/api/v1/reports/{reference_no}", params={"device_id": device_id}, timeout=30)
check("detail readable by the filing device", r.status_code == 200)
r = httpx.get(f"{BASE}/api/v1/reports/{reference_no}", params={"device_id": "wrong-device"}, timeout=30)
check("detail NOT readable by another device", r.status_code == 404)

# ---------------------------------------------------------------------------
print("\nS02/S04/S06 — public content")
# ---------------------------------------------------------------------------
r = httpx.get(f"{BASE}/api/v1/infographics", timeout=30)
check("at most two published infographic slots", r.status_code == 200 and len(r.json()) <= 2)
check("public infographics never include an empty slot",
      all(i["image_path"] and i["title"] for i in r.json()))

r = httpx.get(f"{BASE}/api/v1/hotspots", timeout=30)
check("hotspots returns density points", r.status_code == 200 and len(r.json()) >= 1)
point = r.json()[0]
check("hotspot point exposes ONLY lat/lng/weight",
      set(point.keys()) == {"latitude", "longitude", "weight"}, str(point.keys()))
check("hotspot coordinates are rounded (no premise resolution)",
      len(str(point["latitude"]).split(".")[-1]) <= 3, str(point["latitude"]))

# ---------------------------------------------------------------------------
print("\nD01 — admin authentication")
# ---------------------------------------------------------------------------
r = httpx.post(f"{BASE}/api/v1/admin/login",
               json={"email": ADMIN_EMAIL, "password": "wrong-password"}, timeout=30)
check("bad password rejected", r.status_code == 401)
check("error message does not reveal whether the account exists",
      "Invalid username or password" in r.text, r.text[:120])

r = httpx.post(f"{BASE}/api/v1/admin/login",
               json={"email": ADMIN_EMAIL, "password": ADMIN_PASSWORD}, timeout=30)
check("valid credentials accepted (bcrypt from pgcrypto seed)", r.status_code == 200, r.text[:200])
session = r.json()
check("session is 30 minutes (D01 disclosure)", session["expires_in"] == 1800,
      str(session.get("expires_in")))
auth = {"Authorization": f"Bearer {session['access_token']}"}

r = httpx.get(f"{BASE}/api/v1/admin/reports", timeout=30)
check("admin endpoints reject anonymous access", r.status_code == 401)

# ---------------------------------------------------------------------------
print("\nD02–D05 — dashboard")
# ---------------------------------------------------------------------------
r = httpx.get(f"{BASE}/api/v1/admin/reports", headers=auth, timeout=30)
check("report list returns rows", r.status_code == 200 and r.json()["total"] >= 1, r.text[:200])
row = r.json()["items"][0]
check("list row has NO status column", "status" not in row, str(row.keys()))
check("list row has NO premise_type / violation_type",
      not {"premise_type", "violation_type"} & set(row.keys()))
check("list row carries AI confidence", "ai_confidence" in row)

report_id = row["report_id"]
r = httpx.get(f"{BASE}/api/v1/admin/reports/{report_id}", headers=auth, timeout=30)
check("report detail readable", r.status_code == 200, r.text[:200])
detail = r.json()
check("reporter shown as Anonymous", detail["reporter"] == "Anonymous")
check("classification shown as provenance", detail["classification"]["outcome"] == "PASS")
check("location integrity distance computed",
      detail["location_integrity_metres"] is not None
      and detail["location_integrity_metres"] < 100,
      str(detail["location_integrity_metres"]))

r = httpx.get(f"{BASE}/api/v1/admin/analytics/overview", headers=auth, timeout=30)
check("overview returns panels", r.status_code == 200, r.text[:200])
overview = r.json()
check("overview has NO average-confidence panel", "average_confidence" not in overview)
check("overview has NO pending/verified counts",
      not {"pending_count", "verified_count"} & set(overview.keys()))
check("overview carries the time series", len(overview["reports_over_time"]) >= 1)
check("overview carries top locations", len(overview["top_locations"]) >= 1)

r = httpx.get(f"{BASE}/api/v1/admin/hotspots/clusters", headers=auth, timeout=30)
check("clusters returned with a band", r.status_code == 200 and r.json()[0]["band"] in (1, 2, 3, 4))

r = httpx.get(f"{BASE}/api/v1/admin/reports/export.csv", headers=auth, timeout=30)
check("CSV export succeeds", r.status_code == 200, r.text[:120])
check("CSV is an attachment", "attachment" in r.headers.get("content-disposition", ""))
check("CSV reports the reporter as Anonymous", "Anonymous" in r.text)

# ---------------------------------------------------------------------------
print("\nRead-only administrator model")
# ---------------------------------------------------------------------------
spec = httpx.get(f"{BASE}/openapi.json", timeout=30).json()
write_methods = {"post", "put", "patch", "delete"}
report_writes = [
    f"{m.upper()} {p}"
    for p, ops in spec["paths"].items()
    for m in ops
    if m in write_methods and "/admin/reports" in p
]
check("NO write endpoint exists on admin reports", not report_writes, str(report_writes))

infographic_writes = [
    f"{m.upper()} {p}"
    for p, ops in spec["paths"].items()
    for m in ops
    if m == "post" and "infographics" in p
]
check("NO create endpoint on infographics (two fixed slots)",
      not infographic_writes, str(infographic_writes))

# ---------------------------------------------------------------------------
print(f"\n{'=' * 52}")
print(f"  {passed} passed, {failed} failed")
print(f"{'=' * 52}\n")
sys.exit(1 if failed else 0)
