export type Json = string | number | boolean | null | { [key: string]: Json } | Json[]

export interface Database {
  public: {
    Tables: {
      users: {
        Row: {
          id: string
          email: string
          display_name: string
          username: string | null
          avatar_url: string | null
          bio: string | null
          home_gym_id: string | null
          is_verified: boolean
          onboarding_step: number
          primary_discipline: 'boulder' | 'top_rope' | 'lead' | 'auto_belay' | null
          notifications_enabled: boolean
          is_public: boolean
          created_at: string
          updated_at: string
        }
        Insert: {
          id: string
          email: string
          display_name: string
          username?: string | null
          avatar_url?: string | null
          bio?: string | null
          home_gym_id?: string | null
          is_verified?: boolean
          onboarding_step?: number
          primary_discipline?: 'boulder' | 'top_rope' | 'lead' | 'auto_belay' | null
          notifications_enabled?: boolean
          is_public?: boolean
          created_at?: string
          updated_at?: string
        }
        Update: {
          id?: string
          email?: string
          display_name?: string
          username?: string | null
          avatar_url?: string | null
          bio?: string | null
          home_gym_id?: string | null
          is_verified?: boolean
          onboarding_step?: number
          primary_discipline?: 'boulder' | 'top_rope' | 'lead' | 'auto_belay' | null
          notifications_enabled?: boolean
          is_public?: boolean
          created_at?: string
          updated_at?: string
        }
      }
      gyms: {
        Row: {
          id: string
          name: string
          slug: string
          address_line1: string | null
          address_line2: string | null
          city: string | null
          state_province: string | null
          postal_code: string | null
          country_code: string
          latitude: number | null
          longitude: number | null
          logo_url: string | null
          cover_image_url: string | null
          website_url: string | null
          instagram_handle: string | null
          tier: 'free' | 'pro'
          owner_id: string | null
          is_active: boolean
          created_at: string
          updated_at: string
        }
        Insert: {
          id?: string
          name: string
          slug: string
          address_line1?: string | null
          address_line2?: string | null
          city?: string | null
          state_province?: string | null
          postal_code?: string | null
          country_code?: string
          latitude?: number | null
          longitude?: number | null
          logo_url?: string | null
          cover_image_url?: string | null
          website_url?: string | null
          instagram_handle?: string | null
          tier?: 'free' | 'pro'
          owner_id?: string | null
          is_active?: boolean
          created_at?: string
          updated_at?: string
        }
        Update: {
          id?: string
          name?: string
          slug?: string
          address_line1?: string | null
          address_line2?: string | null
          city?: string | null
          state_province?: string | null
          postal_code?: string | null
          country_code?: string
          latitude?: number | null
          longitude?: number | null
          logo_url?: string | null
          cover_image_url?: string | null
          website_url?: string | null
          instagram_handle?: string | null
          tier?: 'free' | 'pro'
          owner_id?: string | null
          is_active?: boolean
          created_at?: string
          updated_at?: string
        }
      }
      gym_members: {
        Row: {
          id: string
          user_id: string
          gym_id: string
          role: 'member' | 'staff' | 'admin'
          created_at: string
          updated_at: string
        }
        Insert: {
          id?: string
          user_id: string
          gym_id: string
          role?: 'member' | 'staff' | 'admin'
          created_at?: string
          updated_at?: string
        }
        Update: {
          id?: string
          user_id?: string
          gym_id?: string
          role?: 'member' | 'staff' | 'admin'
          created_at?: string
          updated_at?: string
        }
      }
      gym_check_ins: {
        Row: {
          id: string
          user_id: string
          gym_id: string
          expires_at: string
          latitude: number | null
          longitude: number | null
          created_at: string
          updated_at: string
        }
        Insert: {
          id?: string
          user_id: string
          gym_id: string
          expires_at?: string
          latitude?: number | null
          longitude?: number | null
          created_at?: string
          updated_at?: string
        }
        Update: {
          id?: string
          user_id?: string
          gym_id?: string
          expires_at?: string
          latitude?: number | null
          longitude?: number | null
          created_at?: string
          updated_at?: string
        }
      }
      sessions: {
        Row: {
          id: string
          user_id: string
          gym_id: string | null
          crew_id: string | null
          started_at: string
          ended_at: string | null
          climb_count: number
          sends_count: number
          flashes_count: number
          top_grade: string | null
          title: string | null
          notes: string | null
          is_public: boolean
          created_at: string
          updated_at: string
        }
        Insert: {
          id?: string
          user_id: string
          gym_id?: string | null
          crew_id?: string | null
          started_at?: string
          ended_at?: string | null
          climb_count?: number
          sends_count?: number
          flashes_count?: number
          top_grade?: string | null
          title?: string | null
          notes?: string | null
          is_public?: boolean
          created_at?: string
          updated_at?: string
        }
        Update: {
          id?: string
          user_id?: string
          gym_id?: string | null
          crew_id?: string | null
          started_at?: string
          ended_at?: string | null
          climb_count?: number
          sends_count?: number
          flashes_count?: number
          top_grade?: string | null
          title?: string | null
          notes?: string | null
          is_public?: boolean
          created_at?: string
          updated_at?: string
        }
      }
      climb_logs: {
        Row: {
          id: string
          session_id: string
          user_id: string
          style: 'boulder' | 'top_rope' | 'lead' | 'auto_belay'
          grade: string
          grade_order: number | null
          result: 'sent' | 'attempt' | 'flash'
          notes: string | null
          photo_url: string | null
          route_name: string | null
          route_color: string | null
          position: number
          created_at: string
          updated_at: string
        }
        Insert: {
          id?: string
          session_id: string
          user_id: string
          style: 'boulder' | 'top_rope' | 'lead' | 'auto_belay'
          grade: string
          grade_order?: number | null
          result: 'sent' | 'attempt' | 'flash'
          notes?: string | null
          photo_url?: string | null
          route_name?: string | null
          route_color?: string | null
          position?: number
          created_at?: string
          updated_at?: string
        }
        Update: {
          id?: string
          session_id?: string
          user_id?: string
          style?: 'boulder' | 'top_rope' | 'lead' | 'auto_belay'
          grade?: string
          grade_order?: number | null
          result?: 'sent' | 'attempt' | 'flash'
          notes?: string | null
          photo_url?: string | null
          route_name?: string | null
          route_color?: string | null
          position?: number
          created_at?: string
          updated_at?: string
        }
      }
      crews: {
        Row: {
          id: string
          name: string
          slug: string
          description: string | null
          avatar_url: string | null
          gym_id: string | null
          owner_id: string
          is_public: boolean
          invite_code: string | null
          member_count: number
          created_at: string
          updated_at: string
        }
        Insert: {
          id?: string
          name: string
          slug: string
          description?: string | null
          avatar_url?: string | null
          gym_id?: string | null
          owner_id: string
          is_public?: boolean
          invite_code?: string | null
          member_count?: number
          created_at?: string
          updated_at?: string
        }
        Update: {
          id?: string
          name?: string
          slug?: string
          description?: string | null
          avatar_url?: string | null
          gym_id?: string | null
          owner_id?: string
          is_public?: boolean
          invite_code?: string | null
          member_count?: number
          created_at?: string
          updated_at?: string
        }
      }
      crew_members: {
        Row: {
          id: string
          crew_id: string
          user_id: string
          role: 'member' | 'admin'
          invited_at: string | null
          joined_at: string
          created_at: string
          updated_at: string
        }
        Insert: {
          id?: string
          crew_id: string
          user_id: string
          role?: 'member' | 'admin'
          invited_at?: string | null
          joined_at?: string
          created_at?: string
          updated_at?: string
        }
        Update: {
          id?: string
          crew_id?: string
          user_id?: string
          role?: 'member' | 'admin'
          invited_at?: string | null
          joined_at?: string
          created_at?: string
          updated_at?: string
        }
      }
      challenges: {
        Row: {
          id: string
          type: 'daily_global' | 'gym_sponsored' | 'crew'
          gym_id: string | null
          crew_id: string | null
          title: string
          description: string
          criteria: Json
          active_from: string
          active_until: string
          points: number
          created_by: string | null
          is_ai_generated: boolean
          created_at: string
          updated_at: string
        }
        Insert: {
          id?: string
          type: 'daily_global' | 'gym_sponsored' | 'crew'
          gym_id?: string | null
          crew_id?: string | null
          title: string
          description: string
          criteria?: Json
          active_from: string
          active_until: string
          points?: number
          created_by?: string | null
          is_ai_generated?: boolean
          created_at?: string
          updated_at?: string
        }
        Update: {
          id?: string
          type?: 'daily_global' | 'gym_sponsored' | 'crew'
          gym_id?: string | null
          crew_id?: string | null
          title?: string
          description?: string
          criteria?: Json
          active_from?: string
          active_until?: string
          points?: number
          created_by?: string | null
          is_ai_generated?: boolean
          created_at?: string
          updated_at?: string
        }
      }
      challenge_entries: {
        Row: {
          id: string
          challenge_id: string
          user_id: string
          session_id: string | null
          proof_photo_url: string | null
          climb_log_id: string | null
          status: 'pending' | 'approved' | 'rejected'
          points_awarded: number
          created_at: string
          updated_at: string
        }
        Insert: {
          id?: string
          challenge_id: string
          user_id: string
          session_id?: string | null
          proof_photo_url?: string | null
          climb_log_id?: string | null
          status?: 'pending' | 'approved' | 'rejected'
          points_awarded?: number
          created_at?: string
          updated_at?: string
        }
        Update: {
          id?: string
          challenge_id?: string
          user_id?: string
          session_id?: string | null
          proof_photo_url?: string | null
          climb_log_id?: string | null
          status?: 'pending' | 'approved' | 'rejected'
          points_awarded?: number
          created_at?: string
          updated_at?: string
        }
      }
      verification_status: {
        Row: {
          id: string
          user_id: string
          stripe_session_id: string | null
          stripe_report_id: string | null
          status: 'not_started' | 'pending' | 'requires_input' | 'processing' | 'verified' | 'failed' | 'canceled'
          date_of_birth: string | null
          submitted_at: string | null
          verified_at: string | null
          raw_result: Json | null
          created_at: string
          updated_at: string
        }
        Insert: {
          id?: string
          user_id: string
          stripe_session_id?: string | null
          stripe_report_id?: string | null
          status?: 'not_started' | 'pending' | 'requires_input' | 'processing' | 'verified' | 'failed' | 'canceled'
          date_of_birth?: string | null
          submitted_at?: string | null
          verified_at?: string | null
          raw_result?: Json | null
          created_at?: string
          updated_at?: string
        }
        Update: {
          id?: string
          user_id?: string
          stripe_session_id?: string | null
          stripe_report_id?: string | null
          status?: 'not_started' | 'pending' | 'requires_input' | 'processing' | 'verified' | 'failed' | 'canceled'
          date_of_birth?: string | null
          submitted_at?: string | null
          verified_at?: string | null
          raw_result?: Json | null
          created_at?: string
          updated_at?: string
        }
      }
      push_tokens: {
        Row: {
          id: string
          user_id: string
          token: string
          device_id: string
          platform: 'ios' | 'android'
          is_active: boolean
          created_at: string
          updated_at: string
        }
        Insert: {
          id?: string
          user_id: string
          token: string
          device_id: string
          platform: 'ios' | 'android'
          is_active?: boolean
          created_at?: string
          updated_at?: string
        }
        Update: {
          id?: string
          user_id?: string
          token?: string
          device_id?: string
          platform?: 'ios' | 'android'
          is_active?: boolean
          created_at?: string
          updated_at?: string
        }
      }
    }
    Views: {
      crew_leaderboard: {
        Row: {
          crew_id: string
          user_id: string
          display_name: string
          avatar_url: string | null
          username: string | null
          sessions_count: number
          total_sends: number
          total_flashes: number
          top_grade_order: number | null
          rank: number
          refreshed_at: string
        }
      }
      global_leaderboard: {
        Row: {
          user_id: string
          display_name: string
          avatar_url: string | null
          username: string | null
          home_gym_id: string | null
          sessions_count: number
          total_sends: number
          total_flashes: number
          top_grade_order: number | null
          rank: number
          refreshed_at: string
        }
      }
    }
    Functions: Record<string, never>
    Enums: Record<string, never>
  }
}

// Convenience aliases — use these instead of the verbose Database['public']['Tables']['x']['Row']
export type Tables<T extends keyof Database['public']['Tables']> =
  Database['public']['Tables'][T]['Row']

export type TablesInsert<T extends keyof Database['public']['Tables']> =
  Database['public']['Tables'][T]['Insert']

export type TablesUpdate<T extends keyof Database['public']['Tables']> =
  Database['public']['Tables'][T]['Update']

export type Views<T extends keyof Database['public']['Views']> =
  Database['public']['Views'][T]['Row']
