import { Session, User } from '@supabase/supabase-js'
import { create } from 'zustand'
import { Tables } from '../lib/database.types'
import { supabase } from '../lib/supabase'

interface AuthState {
  session: Session | null
  user: User | null
  profile: Tables<'users'> | null
  isLoading: boolean
  isInitialized: boolean

  initialize: () => Promise<void>
  signInWithMagicLink: (email: string) => Promise<void>
  signInWithApple: () => Promise<void>
  signOut: () => Promise<void>
}

export const useAuthStore = create<AuthState>((set, get) => ({
  session: null,
  user: null,
  profile: null,
  isLoading: false,
  isInitialized: false,

  initialize: async () => {
    const { data: { session } } = await supabase.auth.getSession()

    if (session?.user) {
      await fetchProfile(session.user.id, set)
    }

    set({ session, user: session?.user ?? null, isInitialized: true })

    // Keep store in sync with all future auth events
    supabase.auth.onAuthStateChange(async (_event, session) => {
      set({ session, user: session?.user ?? null })

      if (session?.user) {
        await fetchProfile(session.user.id, set)
      } else {
        set({ profile: null })
      }
    })
  },

  signInWithMagicLink: async (email: string) => {
    set({ isLoading: true })
    try {
      const { error } = await supabase.auth.signInWithOtp({
        email,
        options: {
          emailRedirectTo: 'crux://auth/callback',
        },
      })
      if (error) throw error
    } finally {
      set({ isLoading: false })
    }
  },

  signInWithApple: async () => {
    // Dynamically imported so the module doesn't crash on Android/simulator
    const AppleAuthentication = await import('expo-apple-authentication')

    set({ isLoading: true })
    try {
      const credential = await AppleAuthentication.signInAsync({
        requestedScopes: [
          AppleAuthentication.AppleAuthenticationScope.FULL_NAME,
          AppleAuthentication.AppleAuthenticationScope.EMAIL,
        ],
      })

      if (!credential.identityToken) throw new Error('Apple Sign In: no identity token')

      const { error } = await supabase.auth.signInWithIdToken({
        provider: 'apple',
        token: credential.identityToken,
      })
      if (error) throw error
    } finally {
      set({ isLoading: false })
    }
  },

  signOut: async () => {
    set({ isLoading: true })
    try {
      await supabase.auth.signOut()
      set({ session: null, user: null, profile: null })
    } finally {
      set({ isLoading: false })
    }
  },
}))

// Fetches the public.users profile row for a given auth user ID.
// Retries once after 500ms on first sign-in to allow the DB trigger to complete.
async function fetchProfile(
  userId: string,
  set: (partial: Partial<AuthState>) => void,
  attempt = 0
) {
  const { data } = await supabase
    .from('users')
    .select('id, email, display_name, username, avatar_url, is_verified, onboarding_step, is_public, primary_discipline, notifications_enabled, home_gym_id, bio, created_at, updated_at')
    .eq('id', userId)
    .single()

  if (!data && attempt === 0) {
    // Trigger may not have fired yet — wait and retry once
    await new Promise(r => setTimeout(r, 500))
    return fetchProfile(userId, set, 1)
  }

  set({ profile: data ?? null })
}
