@AGENTS.md

## Project Context
This is a React Native + Expo iOS app for tracking climbing sessions and progress.
Stack: React Native, Expo, Supabase, TypeScript.

## Project Rules
- Never use class components — always functional components + hooks
- Supabase for all backend/auth/database — no custom backend
- Keep components under 150 lines; split into smaller files if larger
- Never install a library without asking first
- Always use TypeScript — no plain `.js` files
- File structure: `/components`, `/screens`, `/hooks`, `/lib`, `/types`
- Never hardcode API keys — always use environment variables
- When unsure about a UI decision, ask before implementing
