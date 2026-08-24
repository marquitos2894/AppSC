<script setup>
import { ref } from 'vue'
import { useRouter } from 'vue-router'
import { storeToRefs } from 'pinia'
import { isConfigured } from '@/api/supabaseClient'
import { useAuthStore } from '@/stores/authStore'
import { useToast } from 'primevue/usetoast'

const router = useRouter()
const authStore = useAuthStore()
const toast = useToast()

const { error } = storeToRefs(authStore)

const email = ref('')
const password = ref('')
const enviando = ref(false)
const configurado = isConfigured

async function entrar() {
  if (!email.value || !password.value) return
  enviando.value = true
  try {
    await authStore.signIn(email.value, password.value)
    toast.add({
      severity: 'success',
      summary: 'Sesión iniciada',
      detail: `Bienvenido, ${authStore.email}`,
      life: 3000,
    })
    router.push({ name: 'pedidos' })
  } catch {
    // error mostrado inline en authStore.error
  } finally {
    enviando.value = false
  }
}
</script>

<template>
  <div class="login-wrap">
    <div class="login-panel">
      <div class="app-brand login-brand">
        <div class="app-brand-mark">SC</div>
        <div class="app-brand-text">
          <strong>AppSC</strong>
          <span>Pedidos</span>
        </div>
      </div>

      <div class="login-panel-body">
        <p class="login-kicker">Solicitudes · Análisis · Atención parcial</p>
        <h1 class="login-title">
          Cada repuesto tiene<br />
          una ruta. Sigue la tuya.
        </h1>
        <p class="login-sub">
          Gestión de pedidos de materiales con seguimiento de estados por ítem
          y trazabilidad completa de entregas.
        </p>

        <div class="login-fork" aria-hidden="true">
          <span class="login-fork-line"></span>
          <span class="login-fork-chip login-fork-chip--obs">Observado</span>
          <span class="login-fork-chip login-fork-chip--rej">Rechazado</span>
          <span class="login-fork-chip login-fork-chip--apr">Aprobado</span>
        </div>
      </div>

      <div class="login-panel-foot">
        Panel interno de operaciones · Unidad Corona
      </div>
    </div>

    <div class="login-form-side">
      <div class="login-card">
        <h2 class="login-card-title">Iniciar sesión</h2>
        <p class="login-card-sub">Usa tu cuenta de Supabase Auth.</p>

        <Message v-if="!configurado" severity="warn" :closable="false" style="margin-bottom: 16px">
          Supabase no está configurado. Crea <span class="mono">.env</span> con
          <span class="mono">VITE_SUPABASE_URL</span> y
          <span class="mono">VITE_SUPABASE_ANON_KEY</span> antes de continuar.
        </Message>

        <form class="flex flex-column gap-3" @submit.prevent="entrar">
          <div class="flex flex-column gap-2">
            <label class="field-label" for="login-email">Correo</label>
            <InputText
              id="login-email"
              v-model="email"
              type="email"
              autocomplete="username"
              placeholder="nombre@empresa.pe"
              fluid
              autofocus
            />
          </div>

          <div class="flex flex-column gap-2">
            <label class="field-label" for="login-password">Contraseña</label>
            <Password
              v-model="password"
              input-id="login-password"
              :feedback="false"
              toggle-mask
              autocomplete="current-password"
              placeholder="••••••••"
              fluid
              :input-style="{ width: '100%' }"
            />
          </div>

          <Message v-if="error" severity="error" :closable="false" style="margin-top: 2px">
            {{ error }}
          </Message>

          <Button
            label="Entrar"
            icon="pi pi-sign-in"
            type="submit"
            :loading="enviando"
            :disabled="!email || !password"
            style="margin-top: 4px"
          />
        </form>
      </div>
    </div>
  </div>
</template>

<style scoped>
.field-label {
  font-size: 11px;
  font-weight: 700;
  text-transform: uppercase;
  letter-spacing: 0.08em;
  color: var(--text-muted);
}
</style>
