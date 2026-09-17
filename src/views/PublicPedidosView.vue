<script setup>
import { onMounted, ref, watch } from 'vue'
import { useRoute } from 'vue-router'
import { supabase } from '@/api/supabaseClient'
import { formatDate, formatQty } from '@/utils/format'

const route = useRoute()
const pedidos = ref([])
const loading = ref(true)
const error = ref('')
const detalleVisible = ref(false)
const pedidoSeleccionado = ref(null)
const detalle = ref([])
const loadingDetalle = ref(false)

function etiquetaAtencion(estado) {
  return { PENDIENTE: 'Pendiente', PARCIAL: 'Parcial', COMPLETO: 'Completo' }[estado] || 'No registrado'
}

async function cargar() {
  loading.value = true
  error.value = ''
  try {
    const { data, error: rpcError } = await supabase.rpc('fn_listar_pedidos_publicos', { p_token: route.params.token })
    if (rpcError) throw rpcError
    pedidos.value = data ?? []
  } catch {
    pedidos.value = []
    error.value = 'Este enlace no es válido o su acceso fue revocado.'
  } finally {
    loading.value = false
  }
}

async function abrirDetalle(pedido) {
  pedidoSeleccionado.value = pedido
  detalle.value = []
  detalleVisible.value = true
  loadingDetalle.value = true
  try {
    const { data, error: rpcError } = await supabase.rpc('fn_ver_detalle_pedido_publico', {
      p_token: route.params.token,
      p_pedido_id: pedido.pedido_id,
    })
    if (rpcError) throw rpcError
    detalle.value = data ?? []
  } finally {
    loadingDetalle.value = false
  }
}

onMounted(cargar)
watch(() => route.params.token, cargar)
</script>

<template>
  <main class="public-page">
    <header class="public-header">
      <div>
        <div class="public-brand"><span>SC</span> AppSC</div>
        <h1>Pedidos compartidos</h1>
        <p>Consulta pública de solo lectura.</p>
      </div>
      <Tag value="Solo lectura" icon="pi pi-eye" severity="info" />
    </header>

    <Message v-if="error" severity="error" :closable="false">{{ error }}</Message>

    <template v-else>
      <div v-if="loading" class="public-grid">
        <Skeleton v-for="n in 8" :key="n" height="150px" />
      </div>
      <template v-else>
        <p class="public-total">{{ pedidos.length }} pedido{{ pedidos.length === 1 ? '' : 's' }}</p>
        <div class="public-grid">
          <button v-for="pedido in pedidos" :key="pedido.pedido_id" type="button" class="public-card" @click="abrirDetalle(pedido)">
            <div class="public-card-head">
              <strong>SC{{ pedido.nro_sc }}</strong>
              <Tag :value="pedido.estado_actual" />
            </div>
            <p>{{ pedido.motivo || 'Sin motivo registrado' }}</p>
            <div class="public-card-meta">
              <span><i class="pi pi-calendar"></i> {{ formatDate(pedido.fecha_emision) }}</span>
              <span><i class="pi pi-list"></i> {{ pedido.total_items }} ítems</span>
              <span><i class="pi pi-box"></i> {{ etiquetaAtencion(pedido.estado_atencion) }}</span>
            </div>
            <span v-if="pedido.grupo_costo" class="public-group">{{ pedido.grupo_costo }}</span>
          </button>
        </div>
      </template>
    </template>
  </main>

  <Dialog v-model:visible="detalleVisible" modal :header="pedidoSeleccionado ? `Detalle SC${pedidoSeleccionado.nro_sc}` : 'Detalle'" :style="{ width: 'min(1120px, 96vw)' }">
    <div v-if="loadingDetalle" class="flex justify-content-center p-5"><ProgressSpinner /></div>
    <DataTable v-else :value="detalle" data-key="detalle_id" table-style="min-width: 760px">
      <Column field="nro_parte" header="Nro. parte" style="width: 130px" />
      <Column field="material" header="Material" style="min-width: 220px" />
      <Column header="Solic." style="width: 85px"><template #body="{ data }">{{ formatQty(data.cantidad_solicitada) }}</template></Column>
      <Column header="Aprob." style="width: 85px"><template #body="{ data }">{{ formatQty(data.cantidad_aprobada) }}</template></Column>
      <Column header="Atend." style="width: 85px"><template #body="{ data }">{{ formatQty(data.cantidad_atendida) }}</template></Column>
      <Column header="Estado" style="width: 145px"><template #body="{ data }"><Tag :value="data.estado_actual" /></template></Column>
      <Column header="F. aprox." style="width: 130px"><template #body="{ data }">{{ formatDate(data.fecha_aprox_atencion) }}</template></Column>
    </DataTable>
  </Dialog>
</template>

<style scoped>
.public-page { min-height: 100vh; padding: 32px clamp(18px, 5vw, 72px); background: #f5f8fa; }
.public-header { display: flex; justify-content: space-between; align-items: flex-start; gap: 20px; max-width: 1360px; margin: 0 auto 28px; }
.public-brand { color: #3b6e8f; font-weight: 700; letter-spacing: .04em; }
.public-brand span { display: inline-grid; place-items: center; width: 27px; height: 27px; margin-right: 7px; border-radius: 7px; color: white; background: #3b6e8f; font-size: 11px; }
h1 { margin: 12px 0 4px; color: #1e2a38; font-size: clamp(24px, 4vw, 34px); }
.public-header p, .public-total { color: #64748b; }
.public-total { max-width: 1360px; margin: 0 auto 12px; font-size: 13px; }
.public-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(270px, 1fr)); gap: 14px; max-width: 1360px; margin: 0 auto; }
.public-card { min-height: 154px; padding: 16px; border: 1px solid #dce6ec; border-radius: 12px; background: white; text-align: left; cursor: pointer; transition: transform .15s, box-shadow .15s; }
.public-card:hover { transform: translateY(-2px); box-shadow: 0 10px 24px rgba(30, 58, 78, .11); }
.public-card-head { display: flex; justify-content: space-between; align-items: center; gap: 10px; color: #1e2a38; }
.public-card p { min-height: 38px; margin: 12px 0; color: #475569; font-size: 13px; line-height: 1.45; }
.public-card-meta { display: flex; flex-wrap: wrap; gap: 8px 12px; color: #64748b; font-size: 12px; }
.public-card-meta i { margin-right: 4px; color: #3b6e8f; }
.public-group { display: inline-block; margin-top: 12px; color: #315b76; font-size: 11px; font-weight: 600; }
@media (max-width: 600px) { .public-header { flex-direction: column; } }
</style>
