# EUDI Issuer — frontend (consent)

The issuance consent screen for the authorization-code flow. `issuer-be`'s `/authorize` redirects the browser
here with `?session=<id>`; this page fetches the pending issuance, shows the **PID data to be issued** (styled
like a European national eID issuance screen, with a small **DEMO FLOW** banner), and on **Issue to wallet**
posts the approval and redirects back to the wallet with the authorization code.

Vite + React + Tailwind. Single screen, light theme.

## Config

`VITE_ISSUER_BE_URL` — the issuer backend origin (the FE calls `${VITE_ISSUER_BE_URL}/eudi-issuer/interaction/…`).
Defaults to `http://localhost:3400`.

## Run

```bash
pnpm install
pnpm dev        # http://localhost:5175
pnpm build      # → dist/ (deploy on Vercel; vercel.json rewrites all routes to index.html)
```
