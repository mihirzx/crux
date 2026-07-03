-- =============================================================================
-- CLIMBING COMMUNITY APP — Supabase Database Schema
-- supabase/schema.sql
--
-- Build Order Step 1 of 13: Architecture + database schema
-- "Strava meets Meetup for climbing"
--
-- Paste this entire file into the Supabase SQL editor and run it once.
-- It is idempotent: uses IF NOT EXISTS / OR REPLACE throughout.
-- =============================================================================


-- =============================================================================
-- SECTION 1: EXTENSIONS + HELPER FUNCTIONS
-- =============================================================================

-- pgcrypto gives us gen_random_uuid()
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- pg_trgm gives us GIN indexes for text search (gym names, crew names, display names)
CREATE EXTENSION IF NOT EXISTS "pg_trgm";

-- ---------------------------------------------------------------------------
-- Helper: auto-update updated_at on every row mutation
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.handle_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$;

-- ---------------------------------------------------------------------------
-- Helper: auto-create a public.users profile row when a new auth.users row
-- is inserted (fires via Supabase Auth hook).
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.handle_new_auth_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.users (id, email, display_name)
  VALUES (
    NEW.id,
    NEW.email,
    COALESCE(NEW.raw_user_meta_data->>'full_name', split_part(NEW.email, '@', 1))
  )
  ON CONFLICT (id) DO NOTHING;
  RETURN NEW;
END;
$$;

-- Wire the trigger onto auth.users
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_auth_user();


-- =============================================================================
-- SECTION 2: CORE TABLES — Users, Gyms, Sessions, Climb Logs
-- =============================================================================

-- ---------------------------------------------------------------------------
-- public.users
-- Extends auth.users. One row per authenticated user.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.users (
  id               UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,

  email            TEXT NOT NULL,
  display_name     TEXT NOT NULL CHECK (char_length(display_name) BETWEEN 2 AND 50),
  username         TEXT UNIQUE CHECK (
                     username IS NULL OR (
                       char_length(username) BETWEEN 3 AND 30
                       AND username ~ '^[a-zA-Z0-9_]+$'
                     )
                   ),
  avatar_url       TEXT,
  bio              TEXT CHECK (bio IS NULL OR char_length(bio) <= 300),

  -- Added as deferred FK after gyms table exists
  home_gym_id      UUID,

  is_verified      BOOLEAN NOT NULL DEFAULT FALSE,
  onboarding_step  SMALLINT NOT NULL DEFAULT 0,

  primary_discipline TEXT CHECK (
    primary_discipline IN ('boulder', 'top_rope', 'lead', 'auto_belay')
  ),

  notifications_enabled BOOLEAN NOT NULL DEFAULT TRUE,
  is_public             BOOLEAN NOT NULL DEFAULT TRUE,

  created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TRIGGER users_updated_at
  BEFORE UPDATE ON public.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

-- ---------------------------------------------------------------------------
-- public.gyms
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.gyms (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),

  name             TEXT NOT NULL CHECK (char_length(name) BETWEEN 2 AND 100),
  slug             TEXT NOT NULL UNIQUE CHECK (slug ~ '^[a-z0-9-]+$'),

  address_line1    TEXT,
  address_line2    TEXT,
  city             TEXT,
  state_province   TEXT,
  postal_code      TEXT,
  country_code     CHAR(2) NOT NULL DEFAULT 'US',
  latitude         NUMERIC(9, 6),
  longitude        NUMERIC(9, 6),

  logo_url         TEXT,
  cover_image_url  TEXT,
  website_url      TEXT,
  instagram_handle TEXT,

  -- 'free' = visible in search; 'pro' = branded layer (Step 11)
  tier             TEXT NOT NULL DEFAULT 'free' CHECK (tier IN ('free', 'pro')),

  owner_id         UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  is_active        BOOLEAN NOT NULL DEFAULT TRUE,

  created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TRIGGER gyms_updated_at
  BEFORE UPDATE ON public.gyms
  FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

-- Resolve circular dep: users.home_gym_id → gyms
ALTER TABLE public.users
  ADD CONSTRAINT fk_users_home_gym
  FOREIGN KEY (home_gym_id) REFERENCES public.gyms(id) ON DELETE SET NULL;

-- ---------------------------------------------------------------------------
-- public.gym_members
-- Persistent "I climb here" record — not the same as a check-in.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.gym_members (
  id        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id   UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  gym_id    UUID NOT NULL REFERENCES public.gyms(id) ON DELETE CASCADE,

  role      TEXT NOT NULL DEFAULT 'member' CHECK (role IN ('member', 'staff', 'admin')),

  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  UNIQUE (user_id, gym_id)
);

CREATE TRIGGER gym_members_updated_at
  BEFORE UPDATE ON public.gym_members
  FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

-- ---------------------------------------------------------------------------
-- public.sessions
-- A single gym visit. The atomic unit of the app.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.sessions (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  gym_id      UUID REFERENCES public.gyms(id) ON DELETE SET NULL,
  crew_id     UUID, -- FK added after crews table

  started_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  ended_at    TIMESTAMPTZ,

  -- Denormalized for feed performance (avoids COUNT on every read)
  climb_count      INTEGER NOT NULL DEFAULT 0 CHECK (climb_count >= 0),
  sends_count      INTEGER NOT NULL DEFAULT 0 CHECK (sends_count >= 0),
  flashes_count    INTEGER NOT NULL DEFAULT 0 CHECK (flashes_count >= 0),
  top_grade        TEXT,

  title            TEXT CHECK (title IS NULL OR char_length(title) <= 100),
  notes            TEXT CHECK (notes IS NULL OR char_length(notes) <= 2000),

  is_public        BOOLEAN NOT NULL DEFAULT TRUE,

  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TRIGGER sessions_updated_at
  BEFORE UPDATE ON public.sessions
  FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

-- ---------------------------------------------------------------------------
-- public.climb_logs
-- Individual climbs within a session.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.climb_logs (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id  UUID NOT NULL REFERENCES public.sessions(id) ON DELETE CASCADE,
  user_id     UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,

  style       TEXT NOT NULL CHECK (style IN ('boulder', 'top_rope', 'lead', 'auto_belay')),

  -- V-scale: 'V0'–'V17' | YDS: '5.5'–'5.15d'
  grade       TEXT NOT NULL CHECK (char_length(grade) BETWEEN 1 AND 10),

  -- Normalized numeric for sorting: V0=0…V17=17; YDS 5.5=18…5.15d=34 (set by client)
  grade_order NUMERIC(5, 2),

  result      TEXT NOT NULL CHECK (result IN ('sent', 'attempt', 'flash')),

  notes       TEXT CHECK (notes IS NULL OR char_length(notes) <= 500),
  photo_url   TEXT,
  route_name  TEXT CHECK (route_name IS NULL OR char_length(route_name) <= 100),
  route_color TEXT CHECK (route_color IS NULL OR char_length(route_color) <= 30),

  -- 1-based position within the session (set by client)
  position    SMALLINT NOT NULL DEFAULT 1 CHECK (position >= 1),

  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TRIGGER climb_logs_updated_at
  BEFORE UPDATE ON public.climb_logs
  FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();


-- =============================================================================
-- SECTION 3: SOCIAL TABLES — Crews + Memberships
-- =============================================================================

-- ---------------------------------------------------------------------------
-- public.crews
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.crews (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name        TEXT NOT NULL CHECK (char_length(name) BETWEEN 2 AND 60),
  slug        TEXT NOT NULL UNIQUE CHECK (slug ~ '^[a-z0-9-]+$'),
  description TEXT CHECK (description IS NULL OR char_length(description) <= 500),
  avatar_url  TEXT,

  gym_id      UUID REFERENCES public.gyms(id) ON DELETE SET NULL,
  owner_id    UUID NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,

  is_public   BOOLEAN NOT NULL DEFAULT TRUE,
  invite_code TEXT UNIQUE CHECK (invite_code IS NULL OR char_length(invite_code) = 8),

  -- Denormalized to avoid COUNT on crew list renders
  member_count INTEGER NOT NULL DEFAULT 1 CHECK (member_count >= 0),

  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TRIGGER crews_updated_at
  BEFORE UPDATE ON public.crews
  FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

-- Resolve circular dep: sessions.crew_id → crews
ALTER TABLE public.sessions
  ADD CONSTRAINT fk_sessions_crew
  FOREIGN KEY (crew_id) REFERENCES public.crews(id) ON DELETE SET NULL;

-- ---------------------------------------------------------------------------
-- public.crew_members
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.crew_members (
  id        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  crew_id   UUID NOT NULL REFERENCES public.crews(id) ON DELETE CASCADE,
  user_id   UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,

  role      TEXT NOT NULL DEFAULT 'member' CHECK (role IN ('member', 'admin')),

  invited_at  TIMESTAMPTZ,
  joined_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  UNIQUE (crew_id, user_id)
);

CREATE TRIGGER crew_members_updated_at
  BEFORE UPDATE ON public.crew_members
  FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();


-- =============================================================================
-- SECTION 4: CHALLENGES
-- =============================================================================

-- ---------------------------------------------------------------------------
-- public.challenges
-- daily_global = AI-generated at midnight via Edge Function
-- gym_sponsored = gym admin creates
-- crew = crew admin creates
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.challenges (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),

  type        TEXT NOT NULL CHECK (type IN ('daily_global', 'gym_sponsored', 'crew')),

  gym_id      UUID REFERENCES public.gyms(id) ON DELETE CASCADE,
  crew_id     UUID REFERENCES public.crews(id) ON DELETE CASCADE,

  CONSTRAINT challenges_scope_valid CHECK (
    (type = 'daily_global' AND gym_id IS NULL AND crew_id IS NULL) OR
    (type = 'gym_sponsored' AND gym_id IS NOT NULL AND crew_id IS NULL) OR
    (type = 'crew' AND crew_id IS NOT NULL AND gym_id IS NULL)
  ),

  title       TEXT NOT NULL CHECK (char_length(title) BETWEEN 3 AND 120),
  description TEXT NOT NULL CHECK (char_length(description) BETWEEN 10 AND 1000),

  -- Open-ended challenge rules (min_grade, style, count, etc.) — only justified JSONB
  criteria    JSONB NOT NULL DEFAULT '{}',

  active_from  TIMESTAMPTZ NOT NULL,
  active_until TIMESTAMPTZ NOT NULL,

  CONSTRAINT challenges_window_valid CHECK (active_until > active_from),

  points       INTEGER NOT NULL DEFAULT 100 CHECK (points >= 0),

  -- NULL for AI-generated daily challenges
  created_by   UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  is_ai_generated BOOLEAN NOT NULL DEFAULT FALSE,

  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TRIGGER challenges_updated_at
  BEFORE UPDATE ON public.challenges
  FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

-- ---------------------------------------------------------------------------
-- public.challenge_entries
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.challenge_entries (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  challenge_id  UUID NOT NULL REFERENCES public.challenges(id) ON DELETE CASCADE,
  user_id       UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  session_id    UUID REFERENCES public.sessions(id) ON DELETE SET NULL,

  proof_photo_url TEXT,
  climb_log_id    UUID REFERENCES public.climb_logs(id) ON DELETE SET NULL,

  status        TEXT NOT NULL DEFAULT 'pending'
                CHECK (status IN ('pending', 'approved', 'rejected')),

  points_awarded INTEGER NOT NULL DEFAULT 0 CHECK (points_awarded >= 0),

  UNIQUE (challenge_id, user_id),

  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TRIGGER challenge_entries_updated_at
  BEFORE UPDATE ON public.challenge_entries
  FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();


-- =============================================================================
-- SECTION 5: AUXILIARY TABLES
-- =============================================================================

-- ---------------------------------------------------------------------------
-- public.gym_check_ins
-- Ephemeral presence. expires_at = NOW() + 2 hours.
-- No cron needed — all queries filter WHERE expires_at > NOW().
-- Upsert pattern: INSERT ... ON CONFLICT (user_id, gym_id active) DO UPDATE SET expires_at
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.gym_check_ins (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  gym_id      UUID NOT NULL REFERENCES public.gyms(id) ON DELETE CASCADE,

  expires_at  TIMESTAMPTZ NOT NULL DEFAULT (NOW() + INTERVAL '2 hours'),

  latitude    NUMERIC(9, 6),
  longitude   NUMERIC(9, 6),

  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TRIGGER gym_check_ins_updated_at
  BEFORE UPDATE ON public.gym_check_ins
  FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

-- ---------------------------------------------------------------------------
-- public.verification_status
-- Updated exclusively by Stripe webhook → Edge Function (service-role).
-- No client UPDATE policy = clients cannot self-promote status.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.verification_status (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id           UUID NOT NULL UNIQUE REFERENCES public.users(id) ON DELETE CASCADE,

  stripe_session_id TEXT,
  stripe_report_id  TEXT,

  status            TEXT NOT NULL DEFAULT 'not_started'
                    CHECK (status IN (
                      'not_started', 'pending', 'requires_input',
                      'processing', 'verified', 'failed', 'canceled'
                    )),

  date_of_birth     DATE,
  submitted_at      TIMESTAMPTZ,
  verified_at       TIMESTAMPTZ,

  -- Raw Stripe payload for audit trail — justified JSONB
  raw_result        JSONB,

  created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TRIGGER verification_status_updated_at
  BEFORE UPDATE ON public.verification_status
  FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

-- ---------------------------------------------------------------------------
-- public.push_tokens
-- Expo push tokens. Multiple devices per user allowed.
-- Server-side sends only — never push directly from client.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.push_tokens (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,

  -- Format: ExponentPushToken[xxxxxxxx]
  token       TEXT NOT NULL CHECK (token ~ '^ExponentPushToken\[.+\]$'),

  device_id   TEXT NOT NULL,
  platform    TEXT NOT NULL CHECK (platform IN ('ios', 'android')),
  is_active   BOOLEAN NOT NULL DEFAULT TRUE,

  UNIQUE (user_id, device_id),

  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TRIGGER push_tokens_updated_at
  BEFORE UPDATE ON public.push_tokens
  FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();


-- =============================================================================
-- SECTION 6: INDEXES
-- Each index is annotated with the query pattern it serves.
-- =============================================================================

-- public.users
-- Username lookup (@mention resolution, login)
CREATE UNIQUE INDEX IF NOT EXISTS idx_users_username
  ON public.users (username) WHERE username IS NOT NULL;
-- Home gym FK join (profile screen)
CREATE INDEX IF NOT EXISTS idx_users_home_gym_id
  ON public.users (home_gym_id) WHERE home_gym_id IS NOT NULL;
-- Partner-finder: filter discoverable users
CREATE INDEX IF NOT EXISTS idx_users_is_public
  ON public.users (is_public) WHERE is_public = TRUE;
-- Partner-finder: text search on display_name, @mention autocomplete
CREATE INDEX IF NOT EXISTS idx_users_display_name_trgm
  ON public.users USING GIN (display_name gin_trgm_ops);

-- public.gyms
-- "Find gyms near me" bounding-box query
CREATE INDEX IF NOT EXISTS idx_gyms_lat_lng
  ON public.gyms (latitude, longitude)
  WHERE latitude IS NOT NULL AND longitude IS NOT NULL;
-- Gym search bar
CREATE INDEX IF NOT EXISTS idx_gyms_name_trgm
  ON public.gyms USING GIN (name gin_trgm_ops);
-- Browse active gyms
CREATE INDEX IF NOT EXISTS idx_gyms_is_active
  ON public.gyms (is_active) WHERE is_active = TRUE;
-- Pro gym feature gating
CREATE INDEX IF NOT EXISTS idx_gyms_tier
  ON public.gyms (tier);

-- public.gym_members
-- "Which gyms does this user belong to?" (profile, home gym picker)
CREATE INDEX IF NOT EXISTS idx_gym_members_user_id
  ON public.gym_members (user_id);
-- "Who are the members of this gym?" (gym page)
CREATE INDEX IF NOT EXISTS idx_gym_members_gym_id
  ON public.gym_members (gym_id);
-- Gym admin/staff lookup
CREATE INDEX IF NOT EXISTS idx_gym_members_role
  ON public.gym_members (gym_id, role) WHERE role IN ('staff', 'admin');

-- public.gym_check_ins (hot table — Realtime + frequent queries)
-- "Who is at this gym right now?" — primary check-in query
CREATE INDEX IF NOT EXISTS idx_gym_check_ins_gym_active
  ON public.gym_check_ins (gym_id, expires_at DESC);
-- "Am I checked in?" — user's own status
CREATE INDEX IF NOT EXISTS idx_gym_check_ins_user_active
  ON public.gym_check_ins (user_id, expires_at DESC);
-- Cleanup expired rows (called by Edge Function)
CREATE INDEX IF NOT EXISTS idx_gym_check_ins_expires_at
  ON public.gym_check_ins (expires_at);

-- public.sessions
-- "My recent sessions" — primary user feed query
CREATE INDEX IF NOT EXISTS idx_sessions_user_started
  ON public.sessions (user_id, started_at DESC);
-- "Recent sessions at this gym" — gym activity tab
CREATE INDEX IF NOT EXISTS idx_sessions_gym_started
  ON public.sessions (gym_id, started_at DESC) WHERE gym_id IS NOT NULL;
-- Crew shared sessions
CREATE INDEX IF NOT EXISTS idx_sessions_crew_started
  ON public.sessions (crew_id, started_at DESC) WHERE crew_id IS NOT NULL;
-- "Who's climbing right now" feed (no ended_at)
CREATE INDEX IF NOT EXISTS idx_sessions_active
  ON public.sessions (gym_id, started_at DESC) WHERE ended_at IS NULL;
-- Partner-finder public session feed
CREATE INDEX IF NOT EXISTS idx_sessions_public
  ON public.sessions (started_at DESC) WHERE is_public = TRUE;

-- public.climb_logs
-- "All climbs in this session" — session detail screen
CREATE INDEX IF NOT EXISTS idx_climb_logs_session_position
  ON public.climb_logs (session_id, position);
-- User's full climb history (profile stats)
CREATE INDEX IF NOT EXISTS idx_climb_logs_user_created
  ON public.climb_logs (user_id, created_at DESC);
-- Leaderboard computation: sent climbs in last 30 days (covers mat view refresh)
CREATE INDEX IF NOT EXISTS idx_climb_logs_leaderboard
  ON public.climb_logs (user_id, result, created_at DESC)
  WHERE result IN ('sent', 'flash');
-- Grade distribution chart (user stats)
CREATE INDEX IF NOT EXISTS idx_climb_logs_user_grade
  ON public.climb_logs (user_id, style, grade_order);

-- public.crews
-- Browse public crews
CREATE INDEX IF NOT EXISTS idx_crews_is_public
  ON public.crews (is_public, created_at DESC) WHERE is_public = TRUE;
-- Gym-affiliated crews
CREATE INDEX IF NOT EXISTS idx_crews_gym_id
  ON public.crews (gym_id) WHERE gym_id IS NOT NULL;
-- Join by invite code
CREATE UNIQUE INDEX IF NOT EXISTS idx_crews_invite_code
  ON public.crews (invite_code) WHERE invite_code IS NOT NULL;
-- Crew search bar
CREATE INDEX IF NOT EXISTS idx_crews_name_trgm
  ON public.crews USING GIN (name gin_trgm_ops);

-- public.crew_members
-- "Which crews does this user belong to?"
CREATE INDEX IF NOT EXISTS idx_crew_members_user_id
  ON public.crew_members (user_id);
-- "Who are the members of this crew?"
CREATE INDEX IF NOT EXISTS idx_crew_members_crew_id
  ON public.crew_members (crew_id);
-- Crew admin lookup
CREATE INDEX IF NOT EXISTS idx_crew_members_admin
  ON public.crew_members (crew_id, role) WHERE role = 'admin';

-- public.challenges
-- Active challenges by type (daily feed, gym page, crew page)
CREATE INDEX IF NOT EXISTS idx_challenges_active_window
  ON public.challenges (type, active_from, active_until);
-- Gym's challenges
CREATE INDEX IF NOT EXISTS idx_challenges_gym_id
  ON public.challenges (gym_id, active_until DESC) WHERE gym_id IS NOT NULL;
-- Crew's challenges
CREATE INDEX IF NOT EXISTS idx_challenges_crew_id
  ON public.challenges (crew_id, active_until DESC) WHERE crew_id IS NOT NULL;

-- public.challenge_entries
-- "Which challenges has this user completed?"
CREATE INDEX IF NOT EXISTS idx_challenge_entries_user_id
  ON public.challenge_entries (user_id, created_at DESC);
-- "Who completed this challenge?" (challenge page leaderboard)
CREATE INDEX IF NOT EXISTS idx_challenge_entries_challenge_id
  ON public.challenge_entries (challenge_id, created_at ASC);
-- Points leaderboard per challenge
CREATE INDEX IF NOT EXISTS idx_challenge_entries_points
  ON public.challenge_entries (challenge_id, points_awarded DESC)
  WHERE status = 'approved';

-- public.verification_status
-- Webhook lookup by Stripe session ID
CREATE INDEX IF NOT EXISTS idx_verification_stripe_session
  ON public.verification_status (stripe_session_id)
  WHERE stripe_session_id IS NOT NULL;
-- Filter verified users (age gate)
CREATE INDEX IF NOT EXISTS idx_verification_status_verified
  ON public.verification_status (status) WHERE status = 'verified';

-- public.push_tokens
-- Send push to all active devices for a user
CREATE INDEX IF NOT EXISTS idx_push_tokens_user_active
  ON public.push_tokens (user_id) WHERE is_active = TRUE;


-- =============================================================================
-- SECTION 7: ROW LEVEL SECURITY
-- =============================================================================

ALTER TABLE public.users               ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.gyms                ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.gym_members         ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.gym_check_ins       ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sessions            ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.climb_logs          ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.crews               ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.crew_members        ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.challenges          ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.challenge_entries   ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.verification_status ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.push_tokens         ENABLE ROW LEVEL SECURITY;

-- ---------------------------------------------------------------------------
-- public.users
-- ---------------------------------------------------------------------------
CREATE POLICY "users_select_public"
  ON public.users FOR SELECT TO authenticated
  USING (is_public = TRUE OR id = auth.uid());

CREATE POLICY "users_insert_own"
  ON public.users FOR INSERT TO authenticated
  WITH CHECK (id = auth.uid());

CREATE POLICY "users_update_own"
  ON public.users FOR UPDATE TO authenticated
  USING (id = auth.uid()) WITH CHECK (id = auth.uid());
-- No DELETE policy — hard deletes only via Supabase admin/service-role

-- ---------------------------------------------------------------------------
-- public.gyms
-- ---------------------------------------------------------------------------
-- Active gyms are readable by anyone (including anon — needed for search before login)
CREATE POLICY "gyms_select_active"
  ON public.gyms FOR SELECT TO authenticated, anon
  USING (is_active = TRUE);

CREATE POLICY "gyms_update_owner"
  ON public.gyms FOR UPDATE TO authenticated
  USING (owner_id = auth.uid()) WITH CHECK (owner_id = auth.uid());
-- INSERT/DELETE = service-role only (no client policy)

-- ---------------------------------------------------------------------------
-- public.gym_members
-- ---------------------------------------------------------------------------
CREATE POLICY "gym_members_select_all"
  ON public.gym_members FOR SELECT TO authenticated
  USING (TRUE);

CREATE POLICY "gym_members_insert_own"
  ON public.gym_members FOR INSERT TO authenticated
  WITH CHECK (user_id = auth.uid());

CREATE POLICY "gym_members_delete_own_or_admin"
  ON public.gym_members FOR DELETE TO authenticated
  USING (
    user_id = auth.uid()
    OR EXISTS (
      SELECT 1 FROM public.gym_members gm
      WHERE gm.gym_id = gym_members.gym_id
        AND gm.user_id = auth.uid()
        AND gm.role IN ('admin', 'staff')
    )
  );

CREATE POLICY "gym_members_update_admin"
  ON public.gym_members FOR UPDATE TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.gym_members gm
      WHERE gm.gym_id = gym_members.gym_id
        AND gm.user_id = auth.uid()
        AND gm.role = 'admin'
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.gym_members gm
      WHERE gm.gym_id = gym_members.gym_id
        AND gm.user_id = auth.uid()
        AND gm.role = 'admin'
    )
  );

-- ---------------------------------------------------------------------------
-- public.gym_check_ins
-- ---------------------------------------------------------------------------
-- Any authenticated user can see who is currently at any gym (intentionally open)
CREATE POLICY "gym_check_ins_select_active"
  ON public.gym_check_ins FOR SELECT TO authenticated
  USING (expires_at > NOW());

CREATE POLICY "gym_check_ins_insert_own"
  ON public.gym_check_ins FOR INSERT TO authenticated
  WITH CHECK (user_id = auth.uid());

CREATE POLICY "gym_check_ins_update_own"
  ON public.gym_check_ins FOR UPDATE TO authenticated
  USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());

CREATE POLICY "gym_check_ins_delete_own"
  ON public.gym_check_ins FOR DELETE TO authenticated
  USING (user_id = auth.uid());

-- ---------------------------------------------------------------------------
-- public.sessions
-- ---------------------------------------------------------------------------
CREATE POLICY "sessions_select"
  ON public.sessions FOR SELECT TO authenticated
  USING (user_id = auth.uid() OR is_public = TRUE);

CREATE POLICY "sessions_insert_own"
  ON public.sessions FOR INSERT TO authenticated
  WITH CHECK (user_id = auth.uid());

CREATE POLICY "sessions_update_own"
  ON public.sessions FOR UPDATE TO authenticated
  USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());

CREATE POLICY "sessions_delete_own"
  ON public.sessions FOR DELETE TO authenticated
  USING (user_id = auth.uid());

-- ---------------------------------------------------------------------------
-- public.climb_logs
-- ---------------------------------------------------------------------------
CREATE POLICY "climb_logs_select"
  ON public.climb_logs FOR SELECT TO authenticated
  USING (
    user_id = auth.uid()
    OR EXISTS (
      SELECT 1 FROM public.sessions s
      WHERE s.id = climb_logs.session_id AND s.is_public = TRUE
    )
  );

CREATE POLICY "climb_logs_insert_own"
  ON public.climb_logs FOR INSERT TO authenticated
  WITH CHECK (
    user_id = auth.uid()
    AND EXISTS (
      SELECT 1 FROM public.sessions s
      WHERE s.id = climb_logs.session_id AND s.user_id = auth.uid()
    )
  );

CREATE POLICY "climb_logs_update_own"
  ON public.climb_logs FOR UPDATE TO authenticated
  USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());

CREATE POLICY "climb_logs_delete_own"
  ON public.climb_logs FOR DELETE TO authenticated
  USING (user_id = auth.uid());

-- ---------------------------------------------------------------------------
-- public.crews
-- ---------------------------------------------------------------------------
CREATE POLICY "crews_select_public"
  ON public.crews FOR SELECT TO authenticated
  USING (
    is_public = TRUE
    OR owner_id = auth.uid()
    OR EXISTS (
      SELECT 1 FROM public.crew_members cm
      WHERE cm.crew_id = crews.id AND cm.user_id = auth.uid()
    )
  );

CREATE POLICY "crews_insert_own"
  ON public.crews FOR INSERT TO authenticated
  WITH CHECK (owner_id = auth.uid());

CREATE POLICY "crews_update_owner"
  ON public.crews FOR UPDATE TO authenticated
  USING (owner_id = auth.uid()) WITH CHECK (owner_id = auth.uid());

CREATE POLICY "crews_delete_owner"
  ON public.crews FOR DELETE TO authenticated
  USING (owner_id = auth.uid());

-- ---------------------------------------------------------------------------
-- public.crew_members
-- ---------------------------------------------------------------------------
CREATE POLICY "crew_members_select"
  ON public.crew_members FOR SELECT TO authenticated
  USING (
    user_id = auth.uid()
    OR EXISTS (
      SELECT 1 FROM public.crew_members cm
      WHERE cm.crew_id = crew_members.crew_id AND cm.user_id = auth.uid()
    )
    OR EXISTS (
      SELECT 1 FROM public.crews c
      WHERE c.id = crew_members.crew_id AND c.is_public = TRUE
    )
  );

CREATE POLICY "crew_members_insert_own"
  ON public.crew_members FOR INSERT TO authenticated
  WITH CHECK (user_id = auth.uid());

CREATE POLICY "crew_members_delete_own_or_admin"
  ON public.crew_members FOR DELETE TO authenticated
  USING (
    user_id = auth.uid()
    OR EXISTS (
      SELECT 1 FROM public.crew_members cm
      WHERE cm.crew_id = crew_members.crew_id
        AND cm.user_id = auth.uid()
        AND cm.role = 'admin'
    )
  );

CREATE POLICY "crew_members_update_admin"
  ON public.crew_members FOR UPDATE TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.crew_members cm
      WHERE cm.crew_id = crew_members.crew_id
        AND cm.user_id = auth.uid()
        AND cm.role = 'admin'
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.crew_members cm
      WHERE cm.crew_id = crew_members.crew_id
        AND cm.user_id = auth.uid()
        AND cm.role = 'admin'
    )
  );

-- ---------------------------------------------------------------------------
-- public.challenges
-- ---------------------------------------------------------------------------
CREATE POLICY "challenges_select_active"
  ON public.challenges FOR SELECT TO authenticated
  USING (
    type = 'daily_global'
    OR (type = 'gym_sponsored' AND EXISTS (
      SELECT 1 FROM public.gym_members gm
      WHERE gm.gym_id = challenges.gym_id AND gm.user_id = auth.uid()
    ))
    OR (type = 'crew' AND EXISTS (
      SELECT 1 FROM public.crew_members cm
      WHERE cm.crew_id = challenges.crew_id AND cm.user_id = auth.uid()
    ))
  );

-- Gym admins create gym_sponsored; crew admins create crew; daily_global = service-role only
CREATE POLICY "challenges_insert_scoped"
  ON public.challenges FOR INSERT TO authenticated
  WITH CHECK (
    (type = 'gym_sponsored' AND created_by = auth.uid() AND EXISTS (
      SELECT 1 FROM public.gym_members gm
      WHERE gm.gym_id = challenges.gym_id
        AND gm.user_id = auth.uid()
        AND gm.role = 'admin'
    ))
    OR
    (type = 'crew' AND created_by = auth.uid() AND EXISTS (
      SELECT 1 FROM public.crew_members cm
      WHERE cm.crew_id = challenges.crew_id
        AND cm.user_id = auth.uid()
        AND cm.role = 'admin'
    ))
  );

CREATE POLICY "challenges_update_creator"
  ON public.challenges FOR UPDATE TO authenticated
  USING (created_by = auth.uid()) WITH CHECK (created_by = auth.uid());

-- ---------------------------------------------------------------------------
-- public.challenge_entries
-- ---------------------------------------------------------------------------
CREATE POLICY "challenge_entries_select"
  ON public.challenge_entries FOR SELECT TO authenticated
  USING (
    user_id = auth.uid()
    OR EXISTS (
      SELECT 1 FROM public.challenges ch
      WHERE ch.id = challenge_entries.challenge_id AND ch.created_by = auth.uid()
    )
    OR (
      status = 'approved'
      AND EXISTS (
        SELECT 1 FROM public.challenges ch
        WHERE ch.id = challenge_entries.challenge_id AND ch.type = 'daily_global'
      )
    )
  );

CREATE POLICY "challenge_entries_insert_own"
  ON public.challenge_entries FOR INSERT TO authenticated
  WITH CHECK (user_id = auth.uid());

CREATE POLICY "challenge_entries_update"
  ON public.challenge_entries FOR UPDATE TO authenticated
  USING (
    user_id = auth.uid()
    OR EXISTS (
      SELECT 1 FROM public.challenges ch
      WHERE ch.id = challenge_entries.challenge_id AND ch.created_by = auth.uid()
    )
  )
  WITH CHECK (
    user_id = auth.uid()
    OR EXISTS (
      SELECT 1 FROM public.challenges ch
      WHERE ch.id = challenge_entries.challenge_id AND ch.created_by = auth.uid()
    )
  );

-- Users can withdraw their own pending entry only
CREATE POLICY "challenge_entries_delete_own"
  ON public.challenge_entries FOR DELETE TO authenticated
  USING (user_id = auth.uid() AND status = 'pending');

-- ---------------------------------------------------------------------------
-- public.verification_status
-- ---------------------------------------------------------------------------
CREATE POLICY "verification_status_select_own"
  ON public.verification_status FOR SELECT TO authenticated
  USING (user_id = auth.uid());

CREATE POLICY "verification_status_insert_own"
  ON public.verification_status FOR INSERT TO authenticated
  WITH CHECK (user_id = auth.uid());
-- No UPDATE policy for authenticated role.
-- Only service-role (Stripe webhook Edge Function) can update status/verified_at.

-- ---------------------------------------------------------------------------
-- public.push_tokens
-- ---------------------------------------------------------------------------
CREATE POLICY "push_tokens_select_own"
  ON public.push_tokens FOR SELECT TO authenticated
  USING (user_id = auth.uid());

CREATE POLICY "push_tokens_insert_own"
  ON public.push_tokens FOR INSERT TO authenticated
  WITH CHECK (user_id = auth.uid());

CREATE POLICY "push_tokens_update_own"
  ON public.push_tokens FOR UPDATE TO authenticated
  USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());

CREATE POLICY "push_tokens_delete_own"
  ON public.push_tokens FOR DELETE TO authenticated
  USING (user_id = auth.uid());


-- =============================================================================
-- SECTION 8: MATERIALIZED VIEWS
-- Refreshed every 15 min by Edge Function using service_role key.
-- CONCURRENTLY requires a UNIQUE INDEX — both are created below.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- crew_leaderboard
-- Ranks each crew's members by sends (sent + flash) in the last 30 days.
-- ---------------------------------------------------------------------------
CREATE MATERIALIZED VIEW IF NOT EXISTS public.crew_leaderboard AS
SELECT
  cm.crew_id,
  cm.user_id,
  u.display_name,
  u.avatar_url,
  u.username,
  COUNT(DISTINCT cl.session_id)                                         AS sessions_count,
  COUNT(cl.id) FILTER (WHERE cl.result IN ('sent', 'flash'))            AS total_sends,
  COUNT(cl.id) FILTER (WHERE cl.result = 'flash')                       AS total_flashes,
  MAX(cl.grade_order) FILTER (WHERE cl.result IN ('sent', 'flash'))     AS top_grade_order,
  RANK() OVER (
    PARTITION BY cm.crew_id
    ORDER BY
      COUNT(cl.id) FILTER (WHERE cl.result IN ('sent', 'flash')) DESC,
      MAX(cl.grade_order) FILTER (WHERE cl.result IN ('sent', 'flash')) DESC NULLS LAST,
      MIN(cl.created_at) ASC  -- tiebreaker: earliest send wins
  )                                                                      AS rank,
  NOW()                                                                  AS refreshed_at
FROM public.crew_members cm
JOIN public.users u ON u.id = cm.user_id
LEFT JOIN public.sessions s
  ON  s.user_id  = cm.user_id
  AND s.crew_id  = cm.crew_id
  AND s.started_at >= NOW() - INTERVAL '30 days'
LEFT JOIN public.climb_logs cl
  ON  cl.session_id = s.id
  AND cl.user_id    = cm.user_id
  AND cl.created_at >= NOW() - INTERVAL '30 days'
GROUP BY
  cm.crew_id, cm.user_id,
  u.display_name, u.avatar_url, u.username
WITH DATA;

-- Required for REFRESH CONCURRENTLY
CREATE UNIQUE INDEX IF NOT EXISTS idx_crew_leaderboard_unique
  ON public.crew_leaderboard (crew_id, user_id);

-- Query a specific crew's board in rank order
CREATE INDEX IF NOT EXISTS idx_crew_leaderboard_crew_rank
  ON public.crew_leaderboard (crew_id, rank ASC);

-- ---------------------------------------------------------------------------
-- global_leaderboard
-- Ranks all users by sends in the last 30 days (public sessions only).
-- ---------------------------------------------------------------------------
CREATE MATERIALIZED VIEW IF NOT EXISTS public.global_leaderboard AS
SELECT
  u.id                                                                   AS user_id,
  u.display_name,
  u.avatar_url,
  u.username,
  u.home_gym_id,
  COUNT(DISTINCT cl.session_id)                                          AS sessions_count,
  COUNT(cl.id) FILTER (WHERE cl.result IN ('sent', 'flash'))             AS total_sends,
  COUNT(cl.id) FILTER (WHERE cl.result = 'flash')                        AS total_flashes,
  MAX(cl.grade_order) FILTER (WHERE cl.result IN ('sent', 'flash'))      AS top_grade_order,
  RANK() OVER (
    ORDER BY
      COUNT(cl.id) FILTER (WHERE cl.result IN ('sent', 'flash')) DESC,
      MAX(cl.grade_order) FILTER (WHERE cl.result IN ('sent', 'flash')) DESC NULLS LAST,
      MIN(cl.created_at) ASC
  )                                                                       AS rank,
  NOW()                                                                   AS refreshed_at
FROM public.users u
JOIN public.climb_logs cl
  ON  cl.user_id    = u.id
  AND cl.result     IN ('sent', 'flash')
  AND cl.created_at >= NOW() - INTERVAL '30 days'
JOIN public.sessions s
  ON  s.id          = cl.session_id
  AND s.is_public   = TRUE
GROUP BY
  u.id, u.display_name, u.avatar_url, u.username, u.home_gym_id
WITH DATA;

-- Required for REFRESH CONCURRENTLY
CREATE UNIQUE INDEX IF NOT EXISTS idx_global_leaderboard_unique
  ON public.global_leaderboard (user_id);

-- Leaderboard page pagination
CREATE INDEX IF NOT EXISTS idx_global_leaderboard_rank
  ON public.global_leaderboard (rank ASC);

-- Filter global board by home gym (gym leaderboard tab)
CREATE INDEX IF NOT EXISTS idx_global_leaderboard_gym
  ON public.global_leaderboard (home_gym_id, rank ASC)
  WHERE home_gym_id IS NOT NULL;

-- ---------------------------------------------------------------------------
-- Materialized view access control
-- RLS does not apply to mat views — grant explicitly.
-- Views only expose: display_name, avatar_url, username, aggregate counts.
-- No private data (email, dob, verification) is projected.
-- ---------------------------------------------------------------------------
REVOKE ALL ON public.crew_leaderboard   FROM anon;
REVOKE ALL ON public.global_leaderboard FROM anon;
GRANT  SELECT ON public.crew_leaderboard   TO authenticated;
GRANT  SELECT ON public.global_leaderboard TO authenticated;

-- ---------------------------------------------------------------------------
-- Refresh pattern (Edge Function, runs every 15 min, service_role key):
--
--   REFRESH MATERIALIZED VIEW CONCURRENTLY public.crew_leaderboard;
--   REFRESH MATERIALIZED VIEW CONCURRENTLY public.global_leaderboard;
--
-- CONCURRENTLY = no table lock, reads proceed during refresh.
-- Requires the UNIQUE INDEXes above to exist before first refresh.
-- ---------------------------------------------------------------------------


-- =============================================================================
-- END OF SCHEMA — Step 1 of 13 complete.
--
-- Verification checklist:
--   1. Run this file in Supabase SQL editor (no errors)
--   2. Table Editor: confirm all 12 tables exist with correct columns
--   3. Auth > Policies: every table has its policies listed
--   4. Database > Indexes: spot-check key indexes
--   5. SQL editor: REFRESH MATERIALIZED VIEW CONCURRENTLY public.crew_leaderboard;
--      → must succeed (confirms unique index in place)
--   6. API with anon key: SELECT * FROM verification_status → 0 rows (RLS working)
--
-- Next: Step 2 — Supabase project setup (CLI init, env vars, seed data)
-- =============================================================================
