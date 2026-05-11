-- ============================================================
-- FreelancePilot AI — Complete PostgreSQL Schema
-- Multi-tenant SaaS with Row Level Security
-- ============================================================

-- Enable required extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "vector";        -- pgvector for AI embeddings

-- ============================================================
-- ENUMS
-- ============================================================

CREATE TYPE user_role AS ENUM ('super_admin','workspace_owner','admin','member','readonly');
CREATE TYPE subscription_plan AS ENUM ('free','pro','agency','enterprise');
CREATE TYPE subscription_status AS ENUM ('active','trialing','past_due','canceled','paused');
CREATE TYPE job_platform AS ENUM ('upwork','freelancer','fiverr','contra','peopleperhour','guru','other');
CREATE TYPE job_type AS ENUM ('fixed','hourly');
CREATE TYPE experience_level AS ENUM ('entry','intermediate','expert');
CREATE TYPE pipeline_stage AS ENUM ('discovered','saved','drafted','applied','viewed','interview','negotiation','hired','rejected','archived');
CREATE TYPE proposal_style AS ENUM ('conversational','technical','sales','enterprise','short');
CREATE TYPE proposal_status AS ENUM ('draft','pending_review','approved','submitted','rejected');
CREATE TYPE automation_status AS ENUM ('idle','running','paused','failed','completed');
CREATE TYPE notification_channel AS ENUM ('in_app','email','telegram','discord');
CREATE TYPE notification_type AS ENUM ('high_match_job','proposal_viewed','client_reply','interview','contract','automation_fail','weekly_report','follow_up_needed');

-- ============================================================
-- WORKSPACES (Multi-tenant root)
-- ============================================================

CREATE TABLE workspaces (
  id                uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  name              text NOT NULL,
  slug              text UNIQUE NOT NULL,
  logo_url          text,
  plan              subscription_plan NOT NULL DEFAULT 'free',
  stripe_customer_id text UNIQUE,
  ai_tokens_used    bigint NOT NULL DEFAULT 0,
  ai_tokens_limit   bigint NOT NULL DEFAULT 50000,
  max_members       int NOT NULL DEFAULT 1,
  settings          jsonb NOT NULL DEFAULT '{}',
  created_at        timestamptz NOT NULL DEFAULT now(),
  updated_at        timestamptz NOT NULL DEFAULT now()
);

-- ============================================================
-- USERS & MEMBERSHIPS
-- ============================================================

CREATE TABLE users (
  id                uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  email             text UNIQUE NOT NULL,
  full_name         text,
  avatar_url        text,
  timezone          text DEFAULT 'UTC',
  telegram_chat_id  text,
  discord_webhook   text,
  preferences       jsonb NOT NULL DEFAULT '{}',
  last_active_at    timestamptz,
  created_at        timestamptz NOT NULL DEFAULT now(),
  updated_at        timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE workspace_members (
  id            uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  workspace_id  uuid NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
  user_id       uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  role          user_role NOT NULL DEFAULT 'member',
  invited_by    uuid REFERENCES users(id),
  accepted_at   timestamptz,
  created_at    timestamptz NOT NULL DEFAULT now(),
  UNIQUE (workspace_id, user_id)
);

-- ============================================================
-- FREELANCER PROFILES
-- ============================================================

CREATE TABLE freelancer_profiles (
  id                  uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  workspace_id        uuid NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
  user_id             uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  name                text NOT NULL,
  headline            text,
  bio                 text,
  ai_optimized_bio    text,
  skills              text[] NOT NULL DEFAULT '{}',
  hourly_rate_usd     numeric(10,2),
  experience_level    experience_level DEFAULT 'intermediate',
  languages           text[] NOT NULL DEFAULT '{"English"}',
  portfolio_url       text,
  resume_url          text,
  preferred_platforms job_platform[] NOT NULL DEFAULT '{}',
  preferred_niches    text[] NOT NULL DEFAULT '{}',
  proposal_style      proposal_style DEFAULT 'conversational',
  is_default          boolean NOT NULL DEFAULT false,
  ai_profile_score    int CHECK (ai_profile_score BETWEEN 0 AND 100),
  created_at          timestamptz NOT NULL DEFAULT now(),
  updated_at          timestamptz NOT NULL DEFAULT now()
);

-- ============================================================
-- JOB SOURCES & SCRAPED JOBS
-- ============================================================

CREATE TABLE job_sources (
  id            uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  workspace_id  uuid NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
  platform      job_platform NOT NULL,
  credentials   jsonb,               -- encrypted at app layer
  session_data  jsonb,               -- cookies / tokens
  is_active     boolean NOT NULL DEFAULT true,
  last_synced   timestamptz,
  sync_error    text,
  created_at    timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE scraped_jobs (
  id                  uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  workspace_id        uuid NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
  platform            job_platform NOT NULL,
  platform_job_id     text NOT NULL,
  title               text NOT NULL,
  description         text NOT NULL,
  budget_min          numeric(12,2),
  budget_max          numeric(12,2),
  job_type            job_type,
  experience_level    experience_level,
  client_country      text,
  client_rating       numeric(3,2),
  client_total_spent  numeric(14,2),
  client_verified     boolean DEFAULT false,
  skills_required     text[] NOT NULL DEFAULT '{}',
  proposal_count      int DEFAULT 0,
  url                 text NOT NULL,
  posted_at           timestamptz,
  expires_at          timestamptz,
  is_scam_flagged     boolean DEFAULT false,
  raw_data            jsonb,
  scraped_at          timestamptz NOT NULL DEFAULT now(),
  UNIQUE (workspace_id, platform, platform_job_id)
);

-- ============================================================
-- JOB MATCHES (AI Scored)
-- ============================================================

CREATE TABLE job_matches (
  id                  uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  workspace_id        uuid NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
  job_id              uuid NOT NULL REFERENCES scraped_jobs(id) ON DELETE CASCADE,
  profile_id          uuid NOT NULL REFERENCES freelancer_profiles(id) ON DELETE CASCADE,
  match_score         int NOT NULL CHECK (match_score BETWEEN 0 AND 100),
  win_probability     numeric(5,2) CHECK (win_probability BETWEEN 0 AND 100),
  ai_analysis         jsonb,          -- full AI breakdown
  suggested_rate      numeric(12,2),
  suggested_tone      text,
  risk_level          text,
  scam_score          int CHECK (scam_score BETWEEN 0 AND 100),
  priority            text CHECK (priority IN ('high','medium','low')),
  recommended_action  text,
  embedding           vector(1536),   -- for semantic search
  pipeline_stage      pipeline_stage NOT NULL DEFAULT 'discovered',
  created_at          timestamptz NOT NULL DEFAULT now(),
  updated_at          timestamptz NOT NULL DEFAULT now(),
  UNIQUE (workspace_id, job_id, profile_id)
);

-- ============================================================
-- PROPOSALS
-- ============================================================

CREATE TABLE proposals (
  id                  uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  workspace_id        uuid NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
  job_match_id        uuid REFERENCES job_matches(id) ON DELETE SET NULL,
  job_id              uuid REFERENCES scraped_jobs(id) ON DELETE SET NULL,
  profile_id          uuid NOT NULL REFERENCES freelancer_profiles(id),
  user_id             uuid NOT NULL REFERENCES users(id),
  title               text NOT NULL,
  content             text NOT NULL,
  style               proposal_style NOT NULL DEFAULT 'conversational',
  status              proposal_status NOT NULL DEFAULT 'draft',
  ai_quality_score    int CHECK (ai_quality_score BETWEEN 0 AND 100),
  ai_personalization  int CHECK (ai_personalization BETWEEN 0 AND 100),
  submitted_at        timestamptz,
  viewed_at           timestamptz,
  responded_at        timestamptz,
  view_count          int NOT NULL DEFAULT 0,
  tokens_used         int NOT NULL DEFAULT 0,
  prompt_version      text,
  ai_model_used       text,
  embedding           vector(1536),   -- for similarity matching
  metadata            jsonb NOT NULL DEFAULT '{}',
  created_at          timestamptz NOT NULL DEFAULT now(),
  updated_at          timestamptz NOT NULL DEFAULT now()
);

-- ============================================================
-- CRM — CLIENTS & CONVERSATIONS
-- ============================================================

CREATE TABLE clients (
  id                uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  workspace_id      uuid NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
  platform          job_platform,
  platform_client_id text,
  name              text NOT NULL,
  country           text,
  platform_rating   numeric(3,2),
  total_spent_usd   numeric(14,2),
  payment_verified  boolean DEFAULT false,
  notes             text,
  tags              text[] NOT NULL DEFAULT '{}',
  relationship_score int CHECK (relationship_score BETWEEN 0 AND 100),
  created_at        timestamptz NOT NULL DEFAULT now(),
  updated_at        timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE applications (
  id                uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  workspace_id      uuid NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
  proposal_id       uuid REFERENCES proposals(id),
  client_id         uuid REFERENCES clients(id),
  job_id            uuid REFERENCES scraped_jobs(id),
  pipeline_stage    pipeline_stage NOT NULL DEFAULT 'applied',
  contract_value    numeric(12,2),
  hired_at          timestamptz,
  rejected_at       timestamptz,
  notes             text,
  created_at        timestamptz NOT NULL DEFAULT now(),
  updated_at        timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE interviews (
  id                uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  workspace_id      uuid NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
  application_id    uuid NOT NULL REFERENCES applications(id),
  scheduled_at      timestamptz,
  completed_at      timestamptz,
  outcome           text,
  ai_prep_notes     text,
  questions         jsonb,
  created_at        timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE conversations (
  id                uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  workspace_id      uuid NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
  application_id    uuid REFERENCES applications(id),
  client_id         uuid REFERENCES clients(id),
  platform          job_platform,
  message           text NOT NULL,
  direction         text NOT NULL CHECK (direction IN ('sent','received')),
  is_ai_generated   boolean DEFAULT false,
  sent_at           timestamptz NOT NULL DEFAULT now(),
  created_at        timestamptz NOT NULL DEFAULT now()
);

-- ============================================================
-- AI MEMORY SYSTEM
-- ============================================================

CREATE TABLE ai_memories (
  id                uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  workspace_id      uuid NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
  profile_id        uuid REFERENCES freelancer_profiles(id),
  memory_type       text NOT NULL, -- 'writing_style','tone','niche','success_pattern','phrase'
  content           text NOT NULL,
  embedding         vector(1536),
  weight            numeric(5,4) DEFAULT 1.0,
  usage_count       int NOT NULL DEFAULT 0,
  created_at        timestamptz NOT NULL DEFAULT now(),
  updated_at        timestamptz NOT NULL DEFAULT now()
);

-- ============================================================
-- AUTOMATION
-- ============================================================

CREATE TABLE automation_configs (
  id                uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  workspace_id      uuid NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
  name              text NOT NULL,
  is_enabled        boolean NOT NULL DEFAULT false,
  daily_limit       int NOT NULL DEFAULT 5,
  min_match_score   int NOT NULL DEFAULT 75,
  require_approval  boolean NOT NULL DEFAULT true,
  platforms         job_platform[] NOT NULL DEFAULT '{}',
  schedule_cron     text,
  settings          jsonb NOT NULL DEFAULT '{}',
  created_at        timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE automation_logs (
  id                uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  workspace_id      uuid NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
  config_id         uuid REFERENCES automation_configs(id),
  action            text NOT NULL,
  status            automation_status NOT NULL DEFAULT 'idle',
  job_id            uuid REFERENCES scraped_jobs(id),
  proposal_id       uuid REFERENCES proposals(id),
  error_message     text,
  screenshot_url    text,
  duration_ms       int,
  created_at        timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE browser_sessions (
  id                uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  workspace_id      uuid NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
  platform          job_platform NOT NULL,
  session_data      jsonb,           -- encrypted cookies/tokens
  proxy_used        text,
  is_active         boolean DEFAULT true,
  last_used         timestamptz,
  created_at        timestamptz NOT NULL DEFAULT now()
);

-- ============================================================
-- SUBSCRIPTIONS & BILLING
-- ============================================================

CREATE TABLE subscriptions (
  id                    uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  workspace_id          uuid NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
  stripe_subscription_id text UNIQUE,
  plan                  subscription_plan NOT NULL DEFAULT 'free',
  status                subscription_status NOT NULL DEFAULT 'trialing',
  trial_ends_at         timestamptz,
  current_period_start  timestamptz,
  current_period_end    timestamptz,
  cancel_at             timestamptz,
  created_at            timestamptz NOT NULL DEFAULT now(),
  updated_at            timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE invoices (
  id                uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  workspace_id      uuid NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
  stripe_invoice_id text UNIQUE,
  amount_cents      int NOT NULL,
  currency          text NOT NULL DEFAULT 'usd',
  status            text NOT NULL,
  invoice_pdf_url   text,
  paid_at           timestamptz,
  created_at        timestamptz NOT NULL DEFAULT now()
);

-- ============================================================
-- NOTIFICATIONS
-- ============================================================

CREATE TABLE notifications (
  id                uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  workspace_id      uuid NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
  user_id           uuid REFERENCES users(id),
  type              notification_type NOT NULL,
  channel           notification_channel NOT NULL DEFAULT 'in_app',
  title             text NOT NULL,
  message           text NOT NULL,
  data              jsonb NOT NULL DEFAULT '{}',
  is_read           boolean NOT NULL DEFAULT false,
  sent_at           timestamptz,
  read_at           timestamptz,
  created_at        timestamptz NOT NULL DEFAULT now()
);

-- ============================================================
-- ANALYTICS EVENTS
-- ============================================================

CREATE TABLE analytics_events (
  id                uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  workspace_id      uuid NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
  user_id           uuid REFERENCES users(id),
  event_name        text NOT NULL,
  entity_type       text,
  entity_id         uuid,
  properties        jsonb NOT NULL DEFAULT '{}',
  created_at        timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE ai_usage (
  id                uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  workspace_id      uuid NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
  user_id           uuid REFERENCES users(id),
  feature           text NOT NULL,
  model             text NOT NULL,
  tokens_input      int NOT NULL DEFAULT 0,
  tokens_output     int NOT NULL DEFAULT 0,
  tokens_total      int GENERATED ALWAYS AS (tokens_input + tokens_output) STORED,
  cost_usd          numeric(10,6),
  created_at        timestamptz NOT NULL DEFAULT now()
);

-- ============================================================
-- INDEXES
-- ============================================================

-- Workspace isolation (critical for RLS performance)
CREATE INDEX idx_members_workspace ON workspace_members(workspace_id);
CREATE INDEX idx_members_user ON workspace_members(user_id);
CREATE INDEX idx_profiles_workspace ON freelancer_profiles(workspace_id);
CREATE INDEX idx_jobs_workspace ON scraped_jobs(workspace_id);
CREATE INDEX idx_jobs_platform ON scraped_jobs(platform);
CREATE INDEX idx_jobs_posted ON scraped_jobs(posted_at DESC);
CREATE INDEX idx_matches_workspace ON job_matches(workspace_id);
CREATE INDEX idx_matches_score ON job_matches(match_score DESC);
CREATE INDEX idx_matches_stage ON job_matches(pipeline_stage);
CREATE INDEX idx_proposals_workspace ON proposals(workspace_id);
CREATE INDEX idx_proposals_status ON proposals(status);
CREATE INDEX idx_applications_workspace ON applications(workspace_id);
CREATE INDEX idx_applications_stage ON applications(pipeline_stage);
CREATE INDEX idx_notifications_user ON notifications(user_id, is_read);
CREATE INDEX idx_analytics_workspace_event ON analytics_events(workspace_id, event_name, created_at DESC);
CREATE INDEX idx_ai_usage_workspace ON ai_usage(workspace_id, created_at DESC);
CREATE INDEX idx_ai_memories_workspace ON ai_memories(workspace_id);

-- Vector similarity indexes (pgvector)
CREATE INDEX idx_matches_embedding ON job_matches USING ivfflat (embedding vector_cosine_ops) WITH (lists = 100);
CREATE INDEX idx_proposals_embedding ON proposals USING ivfflat (embedding vector_cosine_ops) WITH (lists = 100);
CREATE INDEX idx_memories_embedding ON ai_memories USING ivfflat (embedding vector_cosine_ops) WITH (lists = 100);

-- ============================================================
-- UPDATED_AT TRIGGER
-- ============================================================

CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN NEW.updated_at = now(); RETURN NEW; END;
$$;

DO $$ DECLARE t text;
BEGIN
  FOR t IN SELECT unnest(ARRAY['workspaces','users','freelancer_profiles',
    'job_matches','proposals','clients','applications','subscriptions'])
  LOOP
    EXECUTE format('CREATE TRIGGER trg_updated_at BEFORE UPDATE ON %I
      FOR EACH ROW EXECUTE FUNCTION update_updated_at()', t);
  END LOOP;
END $$;
