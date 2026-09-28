<script setup>
import { computed, onBeforeUnmount, onMounted, ref } from 'vue'
import { useRouter } from 'vue-router'
import { supabase } from '@/api/supabaseClient'
import { useAuthStore } from '@/stores/authStore'

const router = useRouter()
const auth = useAuthStore()
const visible = ref(false)
const soloNoLeidas = ref(true)
const eventos = ref([])
const noLeidas = ref(0)
const loading = ref(false)
const errorCentro = ref('')
const pushError = ref('')
const pushActivo = ref(false)
const pushDisponible = 'serviceWorker' in navigator && 'PushManager' in window && 'Notification' in window
const clavePublica = import.meta.env.VITE_PUSH_PUBLIC_KEY
let canal

const titulo = computed(() => soloNoLeidas.value ? 'No leídas' : 'Todas')

function fechaCorta(value) {
  return new Intl.DateTimeFormat('es-PE', { dateStyle: 'short', timeStyle: 'short' }).format(new Date(value))
}

function severidad(tipo) {
  if (tipo === 'retraso' || tipo === 'sin_fecha' || tipo === 'rechazado') return 'danger'
  if (tipo === 'vence_hoy' || tipo === 'observado') return 'warn'
  return 'info'
}

async function cargar() {
  if (!auth.isAuthenticated) return
  loading.value = true
  errorCentro.value = ''
  try {
    const [{ data, error }, { data: count, error: countError }] = await Promise.all([
      supabase.rpc('fn_listar_notificaciones_con_equipo', { p_solo_no_leidas: soloNoLeidas.value, p_limite: 100 }),
      supabase.rpc('fn_contar_notificaciones_no_leidas'),
    ])
    if (error) throw error
    if (countError) throw countError
    eventos.value = data ?? []
    noLeidas.value = Number(count ?? 0)
  } catch (e) {
    errorCentro.value = 'No se pudieron cargar las notificaciones. Intenta nuevamente.'
    console.error('No se pudieron cargar las notificaciones:', e)
  } finally {
    loading.value = false
  }
}

async function marcarLeida(evento) {
  if (!evento.leido) {
    const { error } = await supabase.rpc('fn_marcar_notificacion_leida', { p_evento_id: evento.evento_id })
    if (error) return console.error(error)
  }
  await cargar()
}

async function marcarTodas() {
  const { error } = await supabase.rpc('fn_marcar_todas_notificaciones_leidas')
  if (error) return console.error(error)
  await cargar()
}

async function abrirPedido(evento) {
  await marcarLeida(evento)
  visible.value = false
  if (evento.pedido_id) router.push({ name: 'pedidos', query: { pedido: evento.pedido_id } })
}

function claveBytes(base64) {
  const relleno = '='.repeat((4 - base64.length % 4) % 4)
  const normalizado = (base64 + relleno).replace(/-/g, '+').replace(/_/g, '/')
  return Uint8Array.from(atob(normalizado), (caracter) => caracter.charCodeAt(0))
}

async function activarPush() {
  if (!pushDisponible || !clavePublica) return
  pushError.value = ''
  const permiso = await Notification.requestPermission()
  if (permiso !== 'granted') {
    pushError.value = 'El navegador no concedió permiso para mostrar notificaciones.'
    return
  }
  await navigator.serviceWorker.register('/service-worker.js')
  const registro = await navigator.serviceWorker.ready
  const subscription = await registro.pushManager.getSubscription() || await registro.pushManager.subscribe({
    userVisibleOnly: true,
    applicationServerKey: claveBytes(clavePublica),
  })
  const { error } = await supabase.rpc('fn_registrar_suscripcion_push', { p_suscripcion: subscription.toJSON() })
  if (error) throw error
  pushActivo.value = true
}

async function cambiarPush() {
  pushError.value = ''
  try {
    if (pushActivo.value) await desactivarPush()
    else await activarPush()
  } catch (e) {
    pushError.value = e?.message || 'No se pudo actualizar la suscripción de notificaciones.'
  }
}

async function desactivarPush() {
  pushError.value = ''
  const registration = await navigator.serviceWorker.getRegistration()
  const subscription = await registration?.pushManager.getSubscription()
  if (subscription) {
    const { error } = await supabase.rpc('fn_eliminar_suscripcion_push', { p_endpoint: subscription.endpoint })
    if (error) throw error
    await subscription.unsubscribe()
  }
  pushActivo.value = false
}

async function revisarPush() {
  if (!pushDisponible) return
  try {
    const registration = await navigator.serviceWorker.getRegistration()
    const subscription = await registration?.pushManager.getSubscription()
    if (!subscription) {
      pushActivo.value = false
      return
    }
    const { data, error } = await supabase.from('push_suscripcion')
      .select('suscripcion_id').eq('endpoint', subscription.endpoint).eq('active', true).limit(1)
    pushActivo.value = !error && Boolean(data?.length)
  } catch (e) {
    console.warn('No se pudo comprobar la suscripción push:', e)
  }
}

onMounted(() => {
  cargar()
  revisarPush()
  canal = supabase.channel('notificaciones-appsc')
    .on('postgres_changes', { event: '*', schema: 'public', table: 'notificacion_evento' }, () => cargar())
    .subscribe()
})

onBeforeUnmount(() => {
  if (canal) supabase.removeChannel(canal)
})
</script>

<template>
  <Button
    icon="pi pi-bell"
    rounded
    text
    severity="secondary"
    class="notification-bell"
    aria-label="Abrir notificaciones"
    @click="visible = true; cargar(); revisarPush()"
  >
    <i class="pi pi-bell" aria-hidden="true"></i>
    <Badge v-if="noLeidas" :value="noLeidas > 99 ? '99+' : noLeidas" severity="danger" class="notification-count" />
  </Button>

  <Drawer v-model:visible="visible" position="right" header="Notificaciones" style="width: min(460px, 100vw)">
    <div class="notification-tools">
      <SelectButton
        v-model="soloNoLeidas"
        :options="[{ label: 'No leídas', value: true }, { label: 'Todas', value: false }]"
        option-label="label"
        option-value="value"
        @change="cargar"
      />
      <Button v-if="noLeidas" label="Marcar todas" icon="pi pi-check-double" text size="small" @click="marcarTodas" />
    </div>

    <Message v-if="pushDisponible && clavePublica" severity="info" :closable="false" class="push-banner">
      <div class="push-banner-content">
        <span>Recibe avisos aunque AppSC esté cerrada.</span>
        <Button
          :label="pushActivo ? 'Desactivar' : 'Activar notificaciones del navegador'"
          :icon="pushActivo ? 'pi pi-bell-slash' : 'pi pi-bell'"
          text
          size="small"
          @click="cambiarPush"
        />
      </div>
    </Message>
    <Message v-else-if="pushDisponible" severity="secondary" :closable="false" class="push-banner">
      <div class="push-setup-copy">
        <strong>Las notificaciones dentro de AppSC funcionan.</strong>
        <span>Para recibir avisos con la app cerrada faltan <code>VITE_PUSH_PUBLIC_KEY</code> y el despachador de Supabase con sus claves VAPID.</span>
      </div>
    </Message>
    <Message v-if="pushError" severity="warn" :closable="false" class="push-banner">{{ pushError }}</Message>
    <Message v-if="errorCentro" severity="error" :closable="false">{{ errorCentro }}</Message>

    <div v-if="loading && !eventos.length" class="notification-empty">Cargando notificaciones…</div>
    <div v-else-if="!eventos.length" class="notification-empty">
      <i class="pi pi-inbox"></i>
      <span>No hay notificaciones {{ titulo.toLowerCase() }}.</span>
    </div>
    <ul v-else class="notification-list">
      <li v-for="evento in eventos" :key="evento.evento_id" :class="{ unread: !evento.leido }">
        <button type="button" class="notification-item" @click="abrirPedido(evento)">
          <div class="notification-item-head">
            <Tag :value="evento.etiqueta_tipo || evento.tipo" :severity="severidad(evento.tipo)" />
            <span class="notification-date">{{ fechaCorta(evento.creado_en) }}</span>
          </div>
          <div v-if="evento.nro_sc || evento.equipo" class="notification-context">
            <strong v-if="evento.nro_sc" class="notification-sc">SC{{ evento.nro_sc }}</strong>
            <span v-if="evento.equipo" class="notification-equipo"><i class="pi pi-sitemap" aria-hidden="true"></i>{{ evento.equipo }}</span>
          </div>
          <strong class="notification-title">{{ evento.titulo }}</strong>
          <small v-if="evento.estado_actual" class="notification-detail">Estado · {{ evento.estado_actual }}</small>
          <small v-else-if="evento.dias_retraso !== null && evento.dias_retraso !== undefined" class="notification-detail">{{ evento.dias_retraso }} días de retraso</small>
          <small v-else-if="!evento.equipo" class="notification-detail">{{ evento.mensaje }}</small>
        </button>
        <Button v-if="!evento.leido" icon="pi pi-check" text rounded size="small" aria-label="Marcar como leída" @click="marcarLeida(evento)" />
      </li>
    </ul>
  </Drawer>
</template>

<style scoped>
.notification-bell { position: relative; flex: 0 0 auto; }
.notification-count { position: absolute; top: -2px; right: -2px; min-width: 18px; height: 18px; font-size: 10px; }
.notification-tools { display: flex; align-items: center; justify-content: space-between; gap: 8px; margin-bottom: 12px; }
.push-banner { margin-bottom: 14px; }
.push-banner-content { display: grid; gap: 6px; }
.push-setup-copy { display: grid; gap: 4px; }
.push-setup-copy span { font-size: 12px; line-height: 1.45; }
.push-setup-copy code { font-size: 11px; }
.notification-empty { display: grid; justify-items: center; gap: 10px; padding: 42px 16px; color: var(--text-muted); text-align: center; }
.notification-empty i { font-size: 26px; }
.notification-list { display: grid; gap: 8px; margin: 0; padding: 0; list-style: none; }
.notification-list li { display: flex; align-items: flex-start; gap: 5px; padding: 9px; border: 1px solid var(--line); border-radius: 10px; background: white; }
.notification-list li.unread { border-color: #a8c6da; background: #f4f9fc; }
.notification-item { display: grid; flex: 1; gap: 6px; min-width: 0; padding: 0; color: inherit; border: 0; background: transparent; text-align: left; cursor: pointer; }
.notification-item-head { display: flex; justify-content: space-between; gap: 6px; }
.notification-context { display: flex; flex-wrap: wrap; align-items: center; gap: 6px 12px; padding: 2px 0; }
.notification-sc { color: var(--ink-900); font-size: 15px; font-variant-numeric: tabular-nums; }
.notification-equipo { display: inline-flex; align-items: center; gap: 5px; color: #315b76; font-size: 12px; font-weight: 600; }
.notification-equipo i { font-size: 10px; }
.notification-title { color: var(--ink-900); font-size: 12px; font-weight: 600; }
.notification-detail { color: var(--text-muted); font-size: 11px; line-height: 1.4; }
.notification-date { color: var(--text-muted); font-size: 11px; }
.notification-date { white-space: nowrap; }
</style>
