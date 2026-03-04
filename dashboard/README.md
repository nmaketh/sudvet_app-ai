# Vet/Admin Dashboard (Next.js)

This dashboard is for vets, supervisors, and admins.
The Flutter mobile app is for field workers.

## Run (Local)

```powershell
cd dashboard
npm install
npm run dev
```

Open `http://localhost:3000`.

## Environment

Create `.env.local` from `.env.example` if needed:

- `NEXT_PUBLIC_API_URL=http://localhost:8002`

## Backend Pairing

This dashboard should connect to `ops_api` (formerly `api`) on port `8002`, not the Flutter/mobile backend on `8000`.
