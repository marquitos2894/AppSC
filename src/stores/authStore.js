import { defineStore } from 'pinia'
import { supabase } from '@/api/supabaseClient'

function mensajeError(error) {
  switch (error?.message) {
    case 'Invalid login credentials':
      return 'Correo o contraseña incorrectos.'
    case 'Email not confirmed':
      return 'Correo no confirmado. Revisa tu bandeja de entrada.'
    default:
      return error?.message || 'Error de autenticación.'
  }
}

export const useAuthStore = defineStore('auth', {
  state: () => ({
    session: null,
    user: null,
    loading: true,
    error: null,
  }),

  getters: {
    isAuthenticated: (s) => Boolean(s.session?.user),
    email: (s) => s.user?.email ?? null,
  },

  actions: {
    async init() {
      if (this._listenerActivo) return
      this._listenerActivo = true

      supabase.auth.onAuthStateChange((_event, session) => {
        this.session = session
        this.user = session?.user ?? null
        this.loading = false
      })

      const { data } = await supabase.auth.getSession()
      this.session = data.session
      this.user = data.session?.user ?? null
      this.loading = false
    },

    async signIn(email, password) {
      this.error = null
      const { data, error } = await supabase.auth.signInWithPassword({ email, password })
      if (error) {
        this.error = mensajeError(error)
        throw error
      }
      this.session = data.session
      this.user = data.user
      this.loading = false
    },

    async signOut() {
      this.error = null
      const { error } = await supabase.auth.signOut()
      if (error) throw error
      this.session = null
      this.user = null
    },
  },
})
