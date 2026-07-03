import * as AppleAuthentication from 'expo-apple-authentication'
import { useState } from 'react'
import { Alert, Platform, StyleSheet, Text, TextInput, TouchableOpacity, View } from 'react-native'
import { useAuthStore } from '../../stores/authStore'

export default function LoginScreen() {
  const [email, setEmail] = useState('')
  const { signInWithMagicLink, signInWithApple, isLoading } = useAuthStore()

  const handleMagicLink = async () => {
    if (!email.trim()) return
    try {
      await signInWithMagicLink(email.trim())
      Alert.alert('Check your email', `We sent a sign-in link to ${email.trim()}`)
    } catch (err: any) {
      Alert.alert('Error', err.message)
    }
  }

  const handleAppleSignIn = async () => {
    try {
      await signInWithApple()
    } catch (err: any) {
      if (err.code !== 'ERR_REQUEST_CANCELED') {
        Alert.alert('Error', err.message)
      }
    }
  }

  return (
    <View style={styles.container}>
      <Text style={styles.title}>Crux</Text>
      <Text style={styles.subtitle}>Placeholder login — real UI coming in Step 4</Text>

      <TextInput
        style={styles.input}
        placeholder="your@email.com"
        value={email}
        onChangeText={setEmail}
        autoCapitalize="none"
        keyboardType="email-address"
        autoComplete="email"
      />

      <TouchableOpacity style={styles.button} onPress={handleMagicLink} disabled={isLoading}>
        <Text style={styles.buttonText}>{isLoading ? 'Sending…' : 'Send magic link'}</Text>
      </TouchableOpacity>

      {Platform.OS === 'ios' && (
        <AppleAuthentication.AppleAuthenticationButton
          buttonType={AppleAuthentication.AppleAuthenticationButtonType.SIGN_IN}
          buttonStyle={AppleAuthentication.AppleAuthenticationButtonStyle.BLACK}
          cornerRadius={8}
          style={styles.appleButton}
          onPress={handleAppleSignIn}
        />
      )}
    </View>
  )
}

const styles = StyleSheet.create({
  container: { flex: 1, justifyContent: 'center', padding: 32, gap: 16 },
  title: { fontSize: 40, fontWeight: '700', textAlign: 'center' },
  subtitle: { fontSize: 13, color: '#888', textAlign: 'center', marginBottom: 8 },
  input: { borderWidth: 1, borderColor: '#ccc', borderRadius: 8, padding: 14, fontSize: 16 },
  button: { backgroundColor: '#1a1a1a', borderRadius: 8, padding: 16, alignItems: 'center' },
  buttonText: { color: '#fff', fontSize: 16, fontWeight: '600' },
  appleButton: { height: 52 },
})
