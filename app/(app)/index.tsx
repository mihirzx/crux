import { StyleSheet, Text, TouchableOpacity, View } from 'react-native'
import { useAuthStore } from '../../stores/authStore'

export default function HomeScreen() {
  const { user, profile, signOut, isLoading } = useAuthStore()

  return (
    <View style={styles.container}>
      <Text style={styles.title}>Crux</Text>
      <Text style={styles.subtitle}>Placeholder home — real UI coming in Step 4</Text>
      <Text style={styles.info}>Signed in as: {user?.email}</Text>
      {profile && (
        <Text style={styles.info}>Display name: {profile.display_name}</Text>
      )}

      <TouchableOpacity style={styles.button} onPress={signOut} disabled={isLoading}>
        <Text style={styles.buttonText}>{isLoading ? 'Signing out…' : 'Sign out'}</Text>
      </TouchableOpacity>
    </View>
  )
}

const styles = StyleSheet.create({
  container: { flex: 1, justifyContent: 'center', padding: 32, gap: 16 },
  title: { fontSize: 40, fontWeight: '700', textAlign: 'center' },
  subtitle: { fontSize: 13, color: '#888', textAlign: 'center', marginBottom: 8 },
  info: { fontSize: 15, textAlign: 'center', color: '#444' },
  button: { backgroundColor: '#1a1a1a', borderRadius: 8, padding: 16, alignItems: 'center', marginTop: 8 },
  buttonText: { color: '#fff', fontSize: 16, fontWeight: '600' },
})
