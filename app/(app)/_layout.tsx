import { Redirect, Stack } from 'expo-router'
import { useAuthStore } from '../../stores/authStore'

export default function AppLayout() {
  const { session, isInitialized } = useAuthStore()

  // Don't render anything until the persisted session has been checked
  if (!isInitialized) return null

  if (!session) {
    return <Redirect href="/(auth)/login" />
  }

  return <Stack screenOptions={{ headerShown: false }} />
}
