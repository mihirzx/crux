import { useEffect } from 'react'
import { Slot, useRouter, useSegments } from 'expo-router'
import * as Linking from 'expo-linking'
import { supabase } from '../lib/supabase'
import { useAuthStore } from '../stores/authStore'

export default function RootLayout() {
  const { initialize, isInitialized, session } = useAuthStore()
  const router = useRouter()
  const segments = useSegments()

  // Restore persisted session on app open
  useEffect(() => {
    initialize()
  }, [])

  // Handle magic link deep link callback: crux://auth/callback?code=...
  useEffect(() => {
    const handleUrl = async (url: string) => {
      if (!url.includes('auth/callback')) return
      const { data, error } = await supabase.auth.exchangeCodeForSession(url)
      if (error) console.error('Magic link exchange failed:', error.message)
      // onAuthStateChange in the store picks up the new session automatically
    }

    // Handle URL that launched the app (cold start from magic link tap)
    Linking.getInitialURL().then(url => { if (url) handleUrl(url) })

    // Handle URL while app is already open (warm start)
    const subscription = Linking.addEventListener('url', ({ url }) => handleUrl(url))
    return () => subscription.remove()
  }, [])

  // Guard: redirect based on auth state once initialized
  useEffect(() => {
    if (!isInitialized) return

    const inAuthGroup = segments[0] === '(auth)'

    if (!session && !inAuthGroup) {
      router.replace('/(auth)/login')
    } else if (session && inAuthGroup) {
      router.replace('/(app)')
    }
  }, [isInitialized, session, segments])

  return <Slot />
}
