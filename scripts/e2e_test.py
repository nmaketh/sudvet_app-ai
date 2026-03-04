"""End-to-end API test against the running ops_api (http://localhost:8002)."""
import json
import os
import pathlib
import subprocess
import sys

BASE = "http://localhost:8002"
PASS = "Password123!"
tmp = pathlib.Path(os.environ.get("TEMP", "C:/Users/HP/AppData/Local/Temp"))


def api(method, path, token=None, body=None, form=None):
    args = ["curl", "-s", "-X", method, f"{BASE}{path}"]
    if token:
        args += ["-H", f"Authorization: Bearer {token}"]
    if form:
        for k, v in form.items():
            args += ["-F", f"{k}={v}"]
    elif body is not None:
        p = tmp / "_e2e_body.json"
        p.write_text(json.dumps(body))
        args += ["-H", "Content-Type: application/json", "-d", f"@{p}"]
    r = subprocess.run(args, capture_output=True)
    try:
        return json.loads(r.stdout)
    except Exception:
        return {"_raw": r.stdout[:300].decode(errors="replace")}


results = []


def check(ok: bool, name: str, detail: str):
    results.append((ok, name, detail))


# ── 1. Authentication ─────────────────────────────────────────────────────────
cahw_resp  = api("POST", "/auth/login", body={"email": "cahw@cattle.ai",  "password": PASS})
vet_resp   = api("POST", "/auth/login", body={"email": "vet@cattle.ai",   "password": PASS})
admin_resp = api("POST", "/auth/login", body={"email": "admin@cattle.ai", "password": PASS})
cahw  = cahw_resp.get("access_token", "")
vet   = vet_resp.get("access_token", "")
admin = admin_resp.get("access_token", "")
check(bool(cahw and vet and admin),
      "Login all 3 users",
      f"cahw={cahw_resp.get('user',{}).get('role')} vet={vet_resp.get('user',{}).get('role')} admin={admin_resp.get('user',{}).get('role')}")

# ── 2. /auth/me ───────────────────────────────────────────────────────────────
me = api("GET", "/auth/me", token=cahw)
check(me.get("role") == "CAHW", "/auth/me", f"name={me.get('name')} role={me.get('role')}")

# ── 3. Animals ────────────────────────────────────────────────────────────────
animals_r = api("GET", "/animals", token=cahw)
items = (animals_r.get("items", animals_r) if isinstance(animals_r, dict) else animals_r) or []
check(len(items) >= 1, "GET /animals", f"{len(items)} animals returned")
animal_id = items[0]["id"] if items else None

# ── 4. Create case (multipart) ────────────────────────────────────────────────
symptoms = {
    "fever": 1, "skin_nodules": 1, "painless_lumps": 1,
    "enlarged_lymph_nodes": 1, "loss_of_appetite": 1,
    "nasal_discharge": 0, "eye_discharge": 0, "mouth_blisters": 0,
    "foot_lesions": 0, "drooling": 0, "lameness": 0,
    "difficulty_breathing": 0, "coughing": 0, "diarrhoea": 0,
    "depression": 0, "swollen_lymph_nodes": 0, "chest_pain_signs": 0,
    "tongue_sores": 0, "corneal_opacity": 0,
}
payload_str = json.dumps({
    "animalId": animal_id,
    "symptoms": symptoms,
    "temperature": 40.1,
    "severity": 0.75,
    "clientCaseId": "CLI-E2E-FINAL",
})
nc = api("POST", "/cases", token=cahw, form={"payload": payload_str})
case_id = nc.get("id", "")
pred = nc.get("prediction_json") or {}
label = pred.get("label") or pred.get("final_label", "?")
conf = round((nc.get("confidence") or 0) * 100)
engine = pred.get("engine", "?")
check(bool(case_id), "POST /cases (prediction)", f"id={case_id[:8]}.. label={label} conf={conf}% engine={engine}")

# ── 5. GET /cases/{id} ────────────────────────────────────────────────────────
gc = api("GET", f"/cases/{case_id}", token=cahw)
check(gc.get("id") == case_id, "GET /cases/{id}", f"status={gc.get('status')} triage={gc.get('triage_status')}")

# ── 6. Timeline — Flutter-compatible format ───────────────────────────────────
tl = api("GET", f"/cases/{case_id}/timeline", token=cahw)
wf = tl.get("workflowStatus")
check(
    wf is not None and "messages" in tl and "participants" in tl and "events" in tl,
    "GET /timeline (Flutter format)",
    f"workflowStatus={wf} msgs={len(tl.get('messages',[]))} events={len(tl.get('events',[]))} participants={'chwOwner' in (tl.get('participants') or {})}",
)

# ── 7. CAHW sends message ─────────────────────────────────────────────────────
m1 = api("POST", f"/cases/{case_id}/messages", token=cahw,
         body={"message": "Urgent: animal very sick, please review", "senderRole": "cahw", "senderName": "John CAHW"})
check(m1.get("status") == "ok", "CAHW sends chat message", str(m1))

# ── 8. ADMIN assigns to VET ───────────────────────────────────────────────────
vet_id = api("GET", "/auth/me", token=vet).get("id")
assign = api("POST", f"/cases/{case_id}/assign", token=admin, body={"assigned_to_user_id": vet_id})
check(assign.get("triage_status") == "assigned", "ADMIN assigns case to VET",
      f"assigned_to={assign.get('assigned_to_name')} triage={assign.get('triage_status')}")

# ── 9. VET replies in chat ────────────────────────────────────────────────────
m2 = api("POST", f"/cases/{case_id}/messages", token=vet,
         body={"message": "Acknowledged, will review this afternoon", "senderRole": "vet", "senderName": "Dr. Amara Vet"})
check(m2.get("status") == "ok", "VET replies in chat", str(m2))

# ── 10. Final timeline — 2 messages ──────────────────────────────────────────
tl2 = api("GET", f"/cases/{case_id}/timeline", token=vet)
msgs = tl2.get("messages", [])
check(len(msgs) == 2, "Timeline contains 2 chat messages",
      f"workflowStatus={tl2.get('workflowStatus')} msgs={len(msgs)} events={len(tl2.get('events',[]))}")

# ── 11. VET updates case status ───────────────────────────────────────────────
patch = api("PATCH", f"/cases/{case_id}", token=vet,
            body={"status": "in_treatment", "notes": "Started treatment protocol"})
check(patch.get("status") == "in_treatment", "VET PATCH status -> in_treatment",
      f"status={patch.get('status')}")

# ── 12. OTP Signup Step 1 ─────────────────────────────────────────────────────
sr = api("POST", "/auth/signup", body={"name": "NewCHAW User", "email": "e2e_otp_final@cattle.ai", "password": PASS})
sig_tok = sr.get("signupToken", "")
otp     = sr.get("devOtp", "")
check(bool(sig_tok) and bool(otp), "POST /auth/signup (OTP step 1)",
      f"signupToken={sig_tok[:8]}... devOtp={otp} expiresIn={sr.get('expiresInSeconds')}s")

# ── 13. OTP Signup Step 2 ─────────────────────────────────────────────────────
if sig_tok and otp:
    vr = api("POST", "/auth/signup/verify", body={"signupToken": sig_tok, "otp": otp})
    new_role = vr.get("user", {}).get("role", "?")
    new_tok  = vr.get("access_token", "")
    check(new_role == "CAHW" and bool(new_tok), "POST /auth/signup/verify (OTP step 2)",
          f"role={new_role} token={new_tok[:20]}...")
else:
    check(False, "POST /auth/signup/verify", "SKIPPED - no signup token")

# ── 14. Analytics ─────────────────────────────────────────────────────────────
an = api("GET", "/analytics/summary", token=admin)
check("cases_by_disease" in an, "GET /analytics/summary", f"diseases={list(an.get('cases_by_disease',{}).keys())}")

# ── Report ────────────────────────────────────────────────────────────────────
print()
print("=" * 64)
print("  FULL END-TO-END API TEST RESULTS")
print("=" * 64)
passed = 0
for ok, name, detail in results:
    mark = "[PASS]" if ok else "[FAIL]"
    print(f"  {mark}  {name}")
    print(f"          {detail}")
    if ok:
        passed += 1

print()
print(f"  {passed}/{len(results)} passed")
print("=" * 64)

print()
print("Chat transcript:")
for m in msgs:
    role = m.get("senderRole", "?")
    msg  = m.get("message", "")
    ts   = m.get("createdAt", "")[:19]
    print(f"  [{role:6}] {ts}  {msg}")

if passed < len(results):
    sys.exit(1)
