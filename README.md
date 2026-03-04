# SudVet — AI-Powered Cattle Disease Detection System

SudVet is a full-stack veterinary health platform built to support Community Animal Health Workers (CAHWs) in remote areas where access to qualified veterinarians is limited. Field workers use the mobile app to report sick cattle and receive AI-driven disease predictions. Veterinarians review cases, provide clinical guidance, and communicate with field workers through a web dashboard — all in real time.

---

## Live Deployments

| Service | URL |
|---|---|
| Web App (Flutter) | https://incomparable-snickerdoodle-f26e1f.netlify.app |
| Vet Dashboard | https://sudvet-dashboard.vercel.app |
| Backend API | https://sudvet-ops-api.onrender.com |
| API Docs | https://sudvet-ops-api.onrender.com/docs |

**Default test accounts:**

| Role | Email | Password |
|---|---|---|
| Admin | admin@cattle.ai | Password123! |
| Vet | vet@cattle.ai | Password123! |
| CAHW | cahw@cattle.ai | Password123! |

---

## What It Does

- **Field workers (CAHWs)** open the mobile/web app, register an animal, select observed symptoms, and optionally upload a photo. The AI predicts the disease instantly.
- **The AI engine** uses a two-tier approach: a MobileNetV2 CNN for image analysis combined with a Random Forest symptom classifier and a rules engine for ECF/CBPP detection.
- **Veterinarians** log into the dashboard, review flagged cases in a triage queue, claim cases, provide clinical advice (assessment, treatment plan, prescription, follow-up date), and chat directly with the field worker.
- **CAHWs** receive the vet's advice inside their app on the case detail page — in read-only format.
- **Admins** manage users, assign cases, and monitor system health and analytics.

---

## Diseases Detected

| Label | Full Name |
|---|---|
| LSD | Lumpy Skin Disease |
| FMD | Foot and Mouth Disease |
| ECF | East Coast Fever |
| CBPP | Contagious Bovine Pleuropneumonia |
| Normal | No disease detected (healthy animal) |

---

## Architecture Overview

```
┌─────────────────────┐     ┌──────────────────────┐
│   Flutter App        │────▶│   ops_api (FastAPI)   │
│   (CAHW mobile/web)  │     │   PostgreSQL (Supabase)│
└─────────────────────┘     └──────────┬───────────┘
                                        │
                             ┌──────────▼───────────┐
┌─────────────────────┐     │   ML Service          │
│   Next.js Dashboard  │────▶│   MobileNetV2 CNN     │
│   (Vet / Admin)      │     │   Random Forest       │
└─────────────────────┘     │   Rules Engine        │
                             └───────────────────────┘
```

**Stack:**
- **Mobile/Web:** Flutter 3 — BLoC pattern, Go Router, Material 3
- **Backend:** FastAPI + PostgreSQL (Supabase) + SQLAlchemy + Alembic
- **Dashboard:** Next.js 16 + TypeScript + Tailwind CSS + React Query
- **ML:** MobileNetV2 (image) + Random Forest (symptoms) + rules engine
- **Storage:** Supabase Storage (case images)
- **Email:** SendGrid (OTP verification)
- **Deployment:** Docker Compose, Render, Vercel, Netlify

---

## Project Structure

```
sudvet-_app/
├── lib/                        # Flutter app source
│   ├── app/                    # Router, theme, shell
│   ├── core/                   # API clients, models, utils
│   └── features/               # auth, cases, animals, settings, learn
├── ops_api/                    # Backend API (FastAPI)
│   ├── app/
│   │   ├── api/routes/         # auth, cases, animals, analytics, users
│   │   ├── core/               # config, security, OTP, policy
│   │   ├── models/             # SQLAlchemy models
│   │   ├── ml/                 # Bayesian fallback predictor
│   │   └── db/                 # Alembic migrations
│   └── tests/                  # Integration + unit tests
├── dashboard/                  # Next.js vet/admin dashboard
│   └── src/
│       ├── app/                # Pages: login, triage, cases, analytics
│       ├── components/         # Shared UI components
│       └── lib/                # API client, types, case policy
├── cattle_disease_ml/          # ML training + inference service
├── mobile_api/                 # Legacy Flutter backend (kept for reference)
├── deploy/                     # Docker Compose prod + Nginx configs
├── scripts/                    # Developer launcher scripts
└── docker-compose.yml          # Local full-stack setup
```

---

## Installation & Running Locally

### Prerequisites

- [Flutter SDK](https://flutter.dev/docs/get-started/install) (3.x)
- [Docker Desktop](https://www.docker.com/products/docker-desktop)
- [Node.js 18+](https://nodejs.org/) (for dashboard dev)
- Python 3.11+ (for backend dev without Docker)

---

### Option 1 — Full Stack with Docker (Recommended)

This runs the backend API, dashboard, and ML service together.

**1. Clone the repo:**
```bash
git clone https://github.com/nmaketh/sudvet-_app.git
cd sudvet-_app
```

**2. Create your environment file:**
```bash
cp .env.example .env
```

Edit `.env` and fill in:
```env
OPS_SECRET_KEY=your-secret-key-here
DATABASE_URL=postgresql+psycopg2://user:pass@host:5432/dbname
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_SERVICE_ROLE_KEY=your-service-role-key
SUPABASE_STORAGE_BUCKET=case-images
SMTP_HOST=smtp.sendgrid.net
SMTP_PORT=587
SMTP_USER=apikey
SMTP_PASSWORD=your-sendgrid-api-key
SMTP_FROM=your-email@example.com
```

**3. Start all services:**
```bash
docker compose up --build
```

**4. Access the services:**

| Service | URL |
|---|---|
| Dashboard | http://localhost:3000 |
| Backend API docs | http://localhost:8002/docs |
| ML service | http://localhost:8001/health |

---

### Option 2 — Flutter App Only (Against Live Backend)

**1. Install Flutter dependencies:**
```bash
flutter pub get
```

**2. Run on Chrome (web):**
```bash
flutter run -d chrome --web-port 3000 \
  --dart-define=SUDVET_API_BASE_URL=https://sudvet-ops-api.onrender.com
```

**3. Run on Android emulator or connected device:**
```bash
flutter run \
  --dart-define=SUDVET_API_BASE_URL=https://sudvet-ops-api.onrender.com
```

**4. Build release APK:**
```bash
bash scripts/build-release.sh apk
```
The APK will be at `build/app/outputs/flutter-apk/app-release.apk`.

---

### Option 3 — Dashboard Only (Against Live Backend)

```bash
cd dashboard
npm install
NEXT_PUBLIC_API_URL=https://sudvet-ops-api.onrender.com npm run dev
```

Open http://localhost:3000

---

### Option 4 — Backend API Only (Without Docker)

```bash
cd ops_api
python -m venv .venv
source .venv/bin/activate       # Windows: .venv\Scripts\activate
pip install -r requirements.txt
cp .env.example .env            # Fill in your values
uvicorn app.main:app --reload --port 8002
```

API docs available at http://localhost:8002/docs

---

## Running Tests

### Backend — Integration & Unit Tests

```bash
cd ops_api
pip install -r requirements-dev.txt
pytest tests/ -v
```

Expected output: **23 tests passing**
- `test_case_endpoints.py` — 11 HTTP integration tests (case lifecycle, triage, chat)
- `test_case_policy.py` — 10 unit tests (RBAC policy logic)
- `test_health.py` — health endpoint
- `test_auth_register_lockdown.py` — admin-only registration lockdown

### Flutter — Widget Tests

```bash
flutter test
```

---

## Key Features by Role

### CAHW (Field Worker)
- Register cattle with breed, age, location
- Submit disease cases with up to 19 symptoms and a photo
- AI prediction with confidence score, risk level, and disease probabilities
- View vet's clinical advice (assessment, treatment plan, prescription, follow-up date)
- Chat with assigned vet
- Offline-first — cases saved locally and synced when online

### Veterinarian
- Triage queue with filters: All / Claimable / My Cases / Requested for me
- Claim cases, provide clinical review, reject with reason
- Chat with CAHW on claimed cases
- Submit AI feedback (correct/incorrect prediction)
- View AI explainability: probability bars, feature importance, rule triggers, reasoning

### Admin
- Full case visibility across all vets
- Assign cases to specific vets
- User management (view all users by role)
- Analytics dashboard (case counts, disease distribution, vet performance)
- System health and error log monitoring

---

## AI Prediction Flow

```
CAHW selects symptoms + optional photo
         │
         ▼
POST /predict/full
         │
         ├──▶ ML Service (MobileNetV2 + Random Forest)
         │         └── Returns label, confidence, probabilities,
         │               feature importance, grad-CAM URL
         │
         └──▶ Bayesian Fallback (if ML service unavailable)
                   └── Returns label, rule triggers, reasoning
         │
         ▼
Response stored in case record + returned to Flutter app
```

The symptom model was trained on a purpose-built synthetic dataset covering all four diseases plus a healthy (Normal) class, and achieves strong classification performance across all categories. The rules engine provides an additional layer of confidence for ECF and CBPP by cross-checking symptom patterns against clinical criteria.

Diseases: LSD · FMD · ECF · CBPP — plus Normal (healthy, no disease)

---

## Security

- JWT authentication (access + refresh token pair)
- OTP email verification on signup (SendGrid)
- Role-based access control (CAHW / VET / ADMIN) enforced server-side
- Admin-only user registration via `/auth/register`
- CAHW field workers use OTP flow `/auth/signup` → `/auth/signup/verify`
- Chat privacy: VET ↔ CAHW only; ADMINs blocked from case chat
- Rate limiting on all auth endpoints

---

## Deployment Architecture

| Service | Platform | URL |
|---|---|---|
| ops_api (backend) | Render | https://sudvet-ops-api.onrender.com |
| dashboard | Vercel | https://sudvet-dashboard.vercel.app |
| Flutter web | Netlify | https://incomparable-snickerdoodle-f26e1f.netlify.app |
| ML service | Hugging Face Spaces | (separate space) |
| Database | Supabase (PostgreSQL) | Managed cloud |
| File storage | Supabase Storage | case-images bucket |

Production deployments use Docker Compose (`deploy/docker-compose.prod.yml`) with environment variables injected at runtime. No secrets are stored in the repository.

---

## Environment Variables Reference

| Variable | Description |
|---|---|
| `OPS_SECRET_KEY` | JWT signing secret (ops_api) |
| `DATABASE_URL` | PostgreSQL connection string |
| `SUPABASE_URL` | Supabase project URL |
| `SUPABASE_SERVICE_ROLE_KEY` | Supabase service role key |
| `SUPABASE_STORAGE_BUCKET` | Storage bucket name |
| `OPS_CORS_ORIGINS` | Comma-separated allowed origins |
| `SMTP_HOST` | SMTP server host |
| `SMTP_PORT` | SMTP port (587 for TLS) |
| `SMTP_USER` | SMTP username (apikey for SendGrid) |
| `SMTP_PASSWORD` | SMTP password / SendGrid API key |
| `SMTP_FROM` | Sender email address |
| `APP_ENV` | Set to `production` in production |
| `RUN_MIGRATIONS_ON_START` | Auto-run DB migrations on startup |
| `RUN_SEED_ON_START` | Seed default users (dev only) |

---

## Developer Scripts

```bash
# PowerShell
scripts/run-ops-api.ps1         # Start backend API
scripts/run-dashboard.ps1       # Start Next.js dashboard
scripts/run-mobile-api.ps1      # Start mobile API
scripts/run-ml-service.ps1      # Start ML inference service

# Bash
scripts/build-release.sh apk    # Build release APK
scripts/build-release.sh web    # Build Flutter web
```

---

## Analysis

### Objectives Achieved

The core objective of the project was to build a tool that allows Community Animal Health Workers — who typically have no internet access to veterinary experts — to get fast, AI-assisted disease guidance in the field. This was fully achieved:

- **AI disease detection** works with both image and symptom input across all four diseases (LSD, FMD, ECF, CBPP) plus a healthy (Normal) classification. The symptom classifier was trained on synthetic data covering all categories and performs reliably across the full spectrum. The rules engine further validates ECF and CBPP predictions against known clinical symptom patterns.
- **Vet-CAHW communication loop** is fully functional: cases submitted by CAHW are triaged by vets, clinical advice flows back to the field worker in real time
- **Role-based access** ensures each user type only sees and does what is appropriate for their role
- **Offline-first design** allows CAHWs to create cases without internet, which is essential in rural areas
- **Multi-platform delivery**: the same codebase runs as an Android APK, web app, and Windows desktop

### Objectives Partially Met

- **OTP email verification** is configured and functional but depends on SendGrid sender domain verification. In environments where SMTP is not configured, the system falls back gracefully.

### Recommendations

1. **Collect real-world field data** — augmenting the synthetic training dataset with verified clinical cases from veterinary institutions would further improve model robustness and generalization in the field.
2. **Add SMS-based OTP** as a fallback for regions where email is unreliable but mobile data is available.
3. **Introduce a community health worker dashboard** — a simplified read-only view of all their submitted cases and outcomes over time.
4. **Integrate government veterinary databases** to cross-reference case locations against known disease outbreak zones.
5. **Add push notifications** to alert CAHWs when their vet has responded to a case.

---

## License

This project was developed as part of an academic capstone project. All rights reserved.
