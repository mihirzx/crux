import { supabase } from './supabase'

export async function testSupabaseConnection(): Promise<void> {
  const { error } = await supabase
    .from('gyms')
    .select('id')
    .limit(1)

  if (error) {
    console.error('Supabase connection FAILED:', error.message)
    return
  }

  console.log('Supabase connection OK')
}
