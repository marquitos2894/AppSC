<script setup>
import { watch } from 'vue'
import { RouterView, RouterLink, useRouter } from 'vue-router'
import { useAuthStore } from '@/stores/authStore'

const router = useRouter()
const auth = useAuthStore()

watch(
  () => auth.isAuthenticated,
  (authed) => {
    if (!authed && router.currentRoute.value.name !== 'login') {
      router.push({ name: 'login' })
    }
  },
)

async function salir() {
  try {
    await auth.signOut()
    router.push({ name: 'login' })
  } catch (e) {
    console.error(e)
  }
}
</script>

<template>
  <template v-if="auth.isAuthenticated">
    <div class="app-shell">
      <aside class="app-rail">
        <div class="app-brand">
          <div class="app-brand-mark">SC</div>
          <div class="app-brand-text">
            <strong>AppSC</strong>
            <span>Pedidos</span>
          </div>
        </div>

        <nav class="app-nav">
          <RouterLink to="/" class="app-nav-item">
            <i class="pi pi-inbox"></i>
            Pedidos
          </RouterLink>
          <RouterLink to="/items" class="app-nav-item">
            <i class="pi pi-list"></i>
            Ítems
          </RouterLink>
        </nav>

        <div class="app-rail-foot">
          <div class="rail-user">
            <i class="pi pi-user"></i>
            <span class="rail-user-mail mono" :title="auth.email">{{ auth.email }}</span>
          </div>
          <Button
            label="Salir"
            icon="pi pi-sign-out"
            text
            size="small"
            class="rail-logout"
            @click="salir"
          />
        </div>
      </aside>

      <main class="app-main">
        <RouterView />
      </main>
    </div>
  </template>

  <RouterView v-else />

  <Toast position="bottom-right" />
  <ConfirmDialog />
</template>
