# SudVet — Demo Video Script
**Suggested length:** 5–6 minutes
**Tone:** Professional, confident, concise

---

## SCENE 1 — Hook & Introduction (0:00–0:35)
*[Screen: SudVet logo / title card, then slowly pan to the Flutter web app home screen]*

"In rural communities across South Sudan, cattle are the backbone of the economy. But when an animal gets sick, the nearest veterinarian can be hours — or days — away.

SudVet changes that.

It's an AI-powered disease detection platform that puts clinical-grade diagnosis in the hands of Community Animal Health Workers in the field — instantly, offline-capable, and connected to a real vet when it matters most.

Three layers. One system. Let me show you."

---

## SCENE 2 — CAHW: Submitting a Case (0:35–1:50)
*[Screen: Flutter web app — New Case page]*

"A field worker opens SudVet and taps New Case. They select the animal from their registered herd, then check the symptoms they're observing — fever, swollen lymph nodes, nasal discharge, difficulty breathing.

They snap a photo of the affected animal directly from the app."

*[Screen: Symptom checkboxes being selected → camera upload → Submit button]*

"On submission, the AI runs a two-tier analysis in parallel.

A MobileNetV2 convolutional neural network processes the image. Simultaneously, a Random Forest classifier evaluates the symptom profile. A deterministic rules engine then applies epidemiological patterns specific to ECF and CBPP.

All of this resolves in under three seconds."

*[Screen: Result page animating in — disease label, confidence score, probability bars]*

"The result: a predicted disease, a confidence score, risk level, and a full probability breakdown across all five disease classes — Lumpy Skin Disease, Foot and Mouth Disease, East Coast Fever, CBPP, and Normal.

The field worker knows exactly what they're likely dealing with — before they've reached a clinic."

---

## SCENE 3 — CAHW: Case History & Vet Feedback (1:50–2:30)
*[Screen: History tab — list of past cases]*

"Every submitted case is saved to the worker's history. They can track the status of each one in real time.

Opening a case shows the full picture — the AI prediction, the symptoms recorded, and the workflow status."

*[Screen: Case detail → Workflow tab — vet review visible]*

"Once a vet has reviewed the case, the CAHW sees their clinical response right here — the assessment, treatment plan, prescription, and follow-up date.

No phone calls. No waiting. Direct, structured guidance from a qualified professional."

---

## SCENE 4 — CAHW: Requesting a Vet & Chat (2:30–3:05)
*[Screen: Workflow tab — vet request section]*

"The CAHW can request a specific vet by name or email, or leave the case open for any available vet to claim.

Once a vet is assigned, the Chat button activates."

*[Screen: Chat page — messages exchanging]*

"The CAHW types a message. It appears on the right. The vet's reply comes back on the left.

A direct, private channel between the field and the clinic — no third-party apps, no miscommunication."

---

## SCENE 5 — Vet Dashboard: Triage Queue (3:05–3:55)
*[Screen: Vet dashboard login → triage page]*

"Now from the veterinarian's side.

The vet opens the SudVet dashboard and sees their triage queue — organised into four tabs: All Cases, Claimable, My Cases, and Requested for Me.

Cases are colour-coded by predicted disease. Each card shows the risk level, confidence score, and time since submission at a glance."

*[Screen: Vet clicking 'Accept Case']*

"The vet spots a high-risk ECF case requested specifically for them. One click — Accept Case — and it's claimed. They're now the assigned vet."

---

## SCENE 6 — Vet Dashboard: Clinical Review & Chat (3:55–4:50)
*[Screen: Case detail page — AI prediction panel]*

"The case detail page gives the vet everything they need.

The AI reasoning is fully transparent — probability distribution across all diseases, the top contributing symptoms ranked by feature importance, and the model's plain-language justification for its prediction.

The vet can agree, correct the label if needed, or escalate."

*[Screen: Clinical review form being filled in]*

"They fill in the clinical assessment, prescribe treatment, set a follow-up date, and submit.

That review is immediately visible to the CAHW in the mobile app — no sync delay, no manual handoff."

*[Screen: Chat panel in dashboard]*

"And if clarification is needed, the vet opens the chat panel right here on the same page. The conversation is private — visible only to the assigned vet and the CAHW. Admins are intentionally excluded to protect clinical confidentiality."

---

## SCENE 7 — Admin Dashboard (4:50–5:20)
*[Screen: Admin dashboard — analytics page]*

"Administrators have a different view entirely.

The analytics page shows system-wide case volume, disease distribution over time, and vet workload across the team. Trends are visible immediately."

*[Screen: Users page → case assignment]*

"Admins can manage all users across all three roles, assign unresolved cases to specific vets, and monitor system error logs — giving full operational control without touching individual clinical decisions."

---

## SCENE 8 — Architecture (5:20–5:45)
*[Screen: Architecture diagram or clean slide]*

"Under the hood:

The Flutter app — web and mobile — talks to a FastAPI backend running on Render, backed by PostgreSQL on Supabase. The ML inference service runs separately: MobileNetV2 for images, Random Forest for symptoms. If the ML service is unreachable, a Bayesian fallback engine takes over locally — the system never goes dark.

The vet dashboard is a Next.js application deployed on Vercel. The full stack is containerised with Docker Compose for local development."

---

## SCENE 9 — Close (5:45–6:05)
*[Screen: Live URLs — Flutter web app, vet dashboard]*

"SudVet is live right now.

The Flutter web app, the vet dashboard, and the backend API are all deployed and accessible. Test credentials for each role are documented.

The mission was simple: give a field worker in a remote village the same diagnostic confidence as a vet in a clinic.

SudVet delivers that."

---

*End of script.*

---

## Recording Guide

| Scene | Log in as | URL |
|-------|-----------|-----|
| Scenes 2–4 | `cahw@cattle.ai` / `Password123!` | https://startling-gecko-c54150.netlify.app |
| Scenes 5–7 | `vet@cattle.ai` / `Password123!` | https://sudvet-dashboard.vercel.app |
| Scene 7 (admin) | `admin@cattle.ai` / `Password123!` | https://sudvet-dashboard.vercel.app |

**Tips:**
- Record at 1920×1080, browser zoom 100%
- Use OBS Studio or Loom
- Warm up the Render backend before recording — open the app and wait for first login to complete (free tier cold start ~20s)
- Record scenes in order so the case you submit in Scene 2 appears in history for Scene 3
