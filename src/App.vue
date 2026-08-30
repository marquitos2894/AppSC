<script setup>
import { ref, watch } from 'vue'
import { storeToRefs } from 'pinia'
import { RouterView, RouterLink, useRouter } from 'vue-router'
import { useAuthStore } from '@/stores/authStore'
import { useDetallePedidoStore } from '@/stores/detallePedidoStore'
import { useFiltroGlobalStore } from '@/stores/filtroGlobalStore'

const router = useRouter()
const auth = useAuthStore()
const detalleStore = useDetallePedidoStore()
const filtroGlobalStore = useFiltroGlobalStore()

const railCollapsed = ref(false)
const {
  grupoCosto,
  gruposCosto,
  loading: cargandoGruposCosto,
} = storeToRefs(filtroGlobalStore)

watch(
  () => auth.isAuthenticated,
  (authed) => {
    if (authed) {
      filtroGlobalStore.cargarGruposCosto().catch((e) => console.error(e))
    } else {
      filtroGlobalStore.limpiar()
    }
    if (!authed && router.currentRoute.value.name !== 'login') {
      router.push({ name: 'login' })
    }
  },
  { immediate: true },
)

function cambiarGrupoCosto() {
  detalleStore.cerrar()
}

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
    <div class="app-shell" :class="{ 'rail-collapsed': railCollapsed }">
      <aside class="app-rail">
        <div class="app-rail-top">
          <RouterLink to="/" class="app-brand" :aria-label="railCollapsed ? 'AppSC' : undefined">
            <div class="app-brand-mark">SC</div>
            <div v-if="!railCollapsed" class="app-brand-text">
              <strong>AppSC</strong>
              <span>Pedidos</span>
            </div>
          </RouterLink>
          <Button
            :icon="railCollapsed ? 'pi pi-angle-double-right' : 'pi pi-angle-double-left'"
            class="rail-toggle"
            text
            rounded
            size="small"
            :aria-label="railCollapsed ? 'Expandir menú' : 'Colapsar menú'"
            @click="railCollapsed = !railCollapsed"
          />
        </div>

        <nav class="app-nav">
          <RouterLink
            to="/dashboard"
            class="app-nav-item"
            v-tooltip.right="railCollapsed ? 'Dashboard' : undefined"
          >
            <i class="pi pi-chart-bar"></i>
            <span v-if="!railCollapsed">Dashboard</span>
          </RouterLink>
          <RouterLink
            to="/"
            class="app-nav-item"
            v-tooltip.right="railCollapsed ? 'Pedidos' : undefined"
          >
            <i class="pi pi-inbox"></i>
            <span v-if="!railCollapsed">Pedidos</span>
          </RouterLink>
          <RouterLink
            to="/items"
            class="app-nav-item"
            v-tooltip.right="railCollapsed ? 'Ítems' : undefined"
          >
            <i class="pi pi-list"></i>
            <span v-if="!railCollapsed">Ítems</span>
          </RouterLink>
        </nav>

        <div class="app-rail-foot">
          <div class="rail-user">
            <i class="pi pi-user"></i>
            <span v-if="!railCollapsed" class="rail-user-mail mono" :title="auth.email">{{ auth.email }}</span>
          </div>
          <Button
            :label="railCollapsed ? undefined : 'Salir'"
            icon="pi pi-sign-out"
            text
            size="small"
            class="rail-logout"
            v-tooltip.right="railCollapsed ? 'Salir' : undefined"
            @click="salir"
          />
        </div>
      </aside>

      <main class="app-main">
        <div class="global-filter-bar">
          <label for="filtro-grupo-costo" class="global-filter-label">
            <i class="pi pi-filter"></i>
            Grupo de costo
          </label>
          <Select
            id="filtro-grupo-costo"
            v-model="grupoCosto"
            :options="gruposCosto"
            option-label="label"
            option-value="value"
            placeholder="Todos los grupos"
            show-clear
            :loading="cargandoGruposCosto"
            class="global-filter-select"
            @change="cambiarGrupoCosto"
          />
        </div>
        <RouterView />
      </main>
    </div>
  </template>

  <RouterView v-else />

  <Toast position="bottom-right" />
  <ConfirmDialog />
</template>
