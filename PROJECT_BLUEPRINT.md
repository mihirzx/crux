# Climbing App — Project Blueprint
> Read this before writing any code. This is the source of truth.

## What we're building
A climbing community app where the core unit is the Session — 
not just a partner finder. Users log climbs, find partners, 
compete in challenges, and join crews. Gyms pay for a branded 
layer. Think Strava meets Meetup, built for climbing culture.

## Why we're building it step by step
We are NOT one-shotting this. Every layer gets built, tested, 
and optimized before the next layer starts. No skipping ahead.

The build order is:
1. Architecture + database schema (no UI yet)
2. Supabase setup + optimized tables + indexes
3. Auth flow (Supabase Auth + Apple Sign In)
4. Core navigation shell (Expo Router, no real screens yet)
5. Climb logging screen (the daily habit backbone)
6. Session feed + gym check-in
7. Partner + group finding
8. Daily challenges pipeline
9. Crew leaderboards
10. Stripe Identity verification (date unlock gate)
11. B2B gym layer
12. Push notifications
13. Performance audit before any new features

## The three things that kill this app if we get them wrong

### 1. Database performance
- Every table needs proper indexes from day one
- Leaderboards are materialized views, never computed on read
- Gym check-ins expire after 2 hours — use Postgres TTL pattern
- Never do N+1 queries — always join at the database level
- Row Level Security (RLS) on every table from the start

### 2. Stripe Identity lag
The verified date unlock (18+ ID verification) must feel seamless.
Rules:
- Never block the main thread during Stripe Identity flow
- Verification happens in a separate modal, not inline
- Store verified: bool on the user profile, check locally first
- Cache the verification status in Zustand so we never re-check 
  on every render
- Stripe webhook updates Supabase via Edge Function, never client-side
- Optimistic UI: show "verification pending" state immediately, 
  update when webhook fires
- Test on slow network before calling it done

### 3. Caching strategy
Nothing should hit an LLM or an external API more than once 
for the same data.
Rules:
- Daily challenges: generated once at midnight via Edge Function,
  stored in Postgres, read from cache by all users
- Gym pages: cached for 1 hour, invalidated only on gym admin edit
- Leaderboards: materialized view refreshes every 15 minutes
- User profiles: cached in Zustand for the session duration
- Supabase Realtime only for: gym check-ins, active session feed,
  crew chat. Nothing else is real-time.
- GPTCache wraps every LLM call so identical prompts never 
  hit the API twice

## Tech stack (locked in, do not change without asking)
- React Native + Expo (TypeScript)
- Expo Router for navigation (file-based, like Next.js)
- Zustand for state management
- FlashList for all lists (not FlatList)
- Expo Image for all images
- Supabase: Postgres + Realtime + Edge Functions + Auth
- Stripe Identity for age/ID verification
- LiteLLM → Claude Haiku for challenge generation
- LiteLLM → Claude Sonnet for moderation only
- GPTCache for all LLM call caching
- Expo Push Notifications (server-side only, never client-side)

## Core data model
The Session is the atomic unit. Everything connects to it.

User
  └── Sessions (a gym visit)
        └── ClimbLogs (individual climbs in that session)
        └── ChallengeEntries (challenges completed in session)
  └── GymCheckIn (am I here right now?)
  └── CrewMemberships
  └── VerificationStatus (Stripe Identity result)

Gym
  └── Members (users who check in here regularly)
  └── Challenges (gym-sponsored)
  └── ActiveCheckIns (who's here right now, expires 2hrs)

Crew
  └── Members
  └── SharedSessions
  └── Leaderboard (materialized view)

Challenge
  └── Type: daily_global | gym_sponsored | crew
  └── ChallengeEntries (who completed it)

## Performance rules Claude must follow
- Optimistic UI on every user action — update UI before DB write
- Roll back cleanly if the write fails
- No blocking operations on the JS thread
- FlashList for every scrollable list, no exceptions
- Images lazy load with placeholder
- Supabase queries always use .select() with specific columns,
  never select *
- Every Edge Function under 50ms response time target
- Test every feature on iPhone with throttled network (3G) 
  before moving on

## What we do NOT build yet
- Dating/romantic features (phase 2)
- Gym admin dashboard (phase 2)  
- Gear affiliate system (phase 3)
- Brand sponsored challenges (phase 3)
- Android build (after iOS is solid)

## How we work
- Claude Code reads this file at the start of every session
- Before writing any code, Claude states what it's about to do
  and why, and waits for confirmation
- One feature at a time, fully tested before moving on
- If something could be done two ways, Claude presents both 
  with tradeoffs before picking one
- No library installs without asking first
- No touching files unrelated to the current task

## Current step
STEP 1 — Write the full Supabase database schema in SQL.
No UI. No components. Just the schema with proper indexes,
RLS policies, and materialized views. That's all we do today.
