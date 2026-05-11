# FreelancePilot AI

**AI-powered freelance automation platform** — proposal generation, job discovery, CRM, and intelligent workflow automation.

> Built with: Next.js 15 · FastAPI · Supabase · PostgreSQL · pgvector · Redis · Celery · Playwright · OpenAI · Claude · Stripe

---

## Quick Start

### Prerequisites
- Node.js 20+
- Python 3.12+
- Docker & Docker Compose
- pnpm 9+

### 1. Clone & Install

```bash
git clone https://github.com/your-org/freelancepilot-ai
cd freelancepilot-ai
cp .env.example .env
# Fill in your API keys in .env
pnpm install
```

### 2. Start all services (Docker)

```bash
docker compose -f infrastructure/docker/docker-compose.yml up -d
```

This starts: PostgreSQL (with pgvector), Redis, FastAPI backend, Celery worker + scheduler, Next.js frontend.

### 3. Run database migrations

```bash
# Schema + RLS are auto-applied on first startup via docker-entrypoint-initdb.d
# For manual apply:
psql $DATABASE_URL -f packages/database/schema.sql
psql $DATABASE_URL -f packages/database/rls_policies.sql
```

### 4. Open the app

- Web: http://localhost:3000
- API docs: http://localhost:8000/api/docs
- Celery monitor: http://localhost:5555

---

## Architecture Overview

```
apps/
  web/       → Next.js 15 (App Router, React 19, Tailwind, Shadcn)
  api/       → FastAPI (async, repo pattern, service layer)
  worker/    → Celery (job scraping, AI processing, notifications)

packages/
  database/  → PostgreSQL schema + RLS policies
  types/     → Shared TypeScript types
  ai/        → Prompt templates, model router, embeddings
  ui/        → Shared React components
```

## Key Features

| Feature | Description |
|---|---|
| AI Job Matching | Scores jobs 0-100 using OpenAI/Claude with semantic analysis |
| Proposal Studio | Generates personalized proposals in 6 styles |
| AI Memory | Vector-based memory of your writing style and successes |
| Safe Automation | Human-like Playwright automation with mandatory approval gate |
| Kanban Pipeline | Drag-and-drop job pipeline (Discovered → Hired) |
| Analytics | Conversion funnel, win rate by niche, ROI tracking |
| Multi-tenant | Full workspace isolation with PostgreSQL RLS |
| Notifications | Telegram, Email, Discord, in-app alerts |

## Subscription Plans

| Plan | Price | Proposals/mo | AI tokens | Team |
|---|---|---|---|---|
| Free | $0 | 20 | 10k | 1 |
| Pro | $29 | 200 | 100k | 1 |
| Agency | $79 | Unlimited | 500k | 10 |
| Enterprise | Custom | Unlimited | Custom | Unlimited |

## Security

- Row Level Security on all tables (workspace isolation)
- JWT + refresh token rotation
- Rate limiting (per user + per workspace)
- Encrypted browser session data
- CSRF protection
- Audit logging
- IP anomaly detection

## Deployment

**Frontend:** Vercel (auto-deploy on push to main)
**Backend:** Railway (Docker container)
**Database:** Supabase (managed PostgreSQL + pgvector + Realtime)
**Workers:** Railway background service
**CI/CD:** GitHub Actions (lint → test → build → deploy)

---

## Development

```bash
# Run everything in dev mode
pnpm dev

# Run only the API
cd apps/api && uvicorn app.main:app --reload

# Run only the web
cd apps/web && pnpm dev

# Run tests
pnpm test
```

## Environment Variables

See `.env.example` for the complete list of required variables. Key ones:

- `OPENAI_API_KEY` — GPT-4o for job analysis and quality scoring
- `ANTHROPIC_API_KEY` — Claude Sonnet for proposal generation
- `SUPABASE_URL` + `SUPABASE_SERVICE_KEY` — Database + Auth + Storage
- `STRIPE_SECRET_KEY` — Subscription billing
- `TELEGRAM_BOT_TOKEN` — Job alert notifications

---

## Philosophy

FreelancePilot AI is designed to make you a **better** freelancer, not a spam machine. Every automation:

1. Requires human review before any submission
2. Enforces daily limits per platform
3. Simulates human-like timing and behavior
4. Focuses on quality over volume
5. Tracks and learns what actually works

---

MIT License · Built with ❤️ for serious freelancers


## Arabic Features Added
- RTL support
- Arabic proposal generation
- Arabic freelance platform scrapers
- ERP & accounting focused AI workflows
