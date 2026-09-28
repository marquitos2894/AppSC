<script setup>
import { computed, onMounted, ref } from 'vue'
import { supabase } from '@/api/supabaseClient'
import { formatDate, formatQty } from '@/utils/format'
import PedidoResumenDialog from '@/components/PedidoResumenDialog.vue'

const pedidos = ref([])
const alertas = ref([])
const errorAlertas = ref('')
const loading = ref(true)
const error = ref('')
const resumenVisible = ref(false)
const pedidoSeleccionado = ref(null)
const resumenItems = ref([])
const loadingDetalle = ref(false)
const busquedaSc = ref('')
const busquedaItem = ref('')
const estado = ref(null)
const grupoCosto = ref(null)
const estados = ref([])
const gruposCosto = ref([])
const first = ref(0)
const rows = ref(12)
const total = ref(0)

const totalTexto = computed(() => `${total.value} pedido${total.value === 1 ? '' : 's'}`)

function etiquetaAtencion(valor) {
  return { PENDIENTE: 'Pendiente', PARCIAL: 'Parcial', COMPLETO: 'Completo' }[valor] || 'No registrado'
}

function normalizarItems(items) {
  return (items ?? []).map((item) => ({
    ...item,
    estados_catalogo: { nombre: item.estado_actual || 'No registrado' },
  }))
}

async function cargarCatalogos() {
  const { data, error: rpcError } = await supabase.rpc('fn_listar_filtros_pedidos_publicos_permanente')
  if (rpcError) throw rpcError
  estados.value = [...new Set((data ?? []).map((pedido) => pedido.estado_actual).filter(Boolean))]
      .sort((a, b) => a.localeCompare(b, 'es'))
      .map((nombre) => ({ label: nombre, value: nombre }))
  gruposCosto.value = [...new Set((data ?? []).map((pedido) => pedido.grupo_costo).filter(Boolean))]
      .sort((a, b) => a.localeCompare(b, 'es'))
      .map((nombre) => ({ label: nombre, value: nombre }))
}

async function cargar({ reiniciar = false } = {}) {
  if (reiniciar) first.value = 0
  loading.value = true
  error.value = ''
  errorAlertas.value = ''
  try {
    const filtros = {
      p_busqueda_sc: busquedaSc.value.trim() || null,
      p_busqueda_item: busquedaItem.value.trim() || null,
      p_estado: estado.value || null,
      p_grupo_costo: grupoCosto.value || null,
    }
    const [{ data, error: rpcError }, { data: datosAlertas, error: rpcErrorAlertas }] = await Promise.all([
      supabase.rpc('fn_listar_pedidos_publicos_paginado', {
        ...filtros,
        p_pagina: Math.floor(first.value / rows.value) + 1,
        p_por_pagina: rows.value,
      }),
      supabase.rpc('fn_alertas_publicas_vigentes', filtros),
    ])
    if (rpcError) throw rpcError
    pedidos.value = data ?? []
    alertas.value = rpcErrorAlertas ? [] : (datosAlertas ?? [])
    if (rpcErrorAlertas) errorAlertas.value = 'Las alertas no están disponibles temporalmente.'
    total.value = Number(data?.[0]?.total_registros ?? 0)
  } catch (e) {
    pedidos.value = []
    total.value = 0
    error.value = 'La consulta pública no está disponible en este momento.'
  } finally {
    loading.value = false
  }
}

async function cargarResumen(pedido) {
  const { data, error: rpcError } = await supabase.rpc('fn_resumen_pedido_publico_permanente', {
    p_pedido_id: pedido.pedido_id,
  })
  if (rpcError) throw rpcError
  return normalizarItems(data)
}

async function abrirResumen(pedido) {
  pedidoSeleccionado.value = pedido
  resumenItems.value = []
  loadingDetalle.value = true
  try {
    resumenItems.value = await cargarResumen(pedido)
    resumenVisible.value = true
  } catch {
    error.value = 'No se pudo generar el resumen del pedido.'
  } finally {
    loadingDetalle.value = false
  }
}

function alertasPedido(pedidoId) {
  return alertas.value.filter((alerta) => Number(alerta.pedido_id) === Number(pedidoId))
}

function etiquetaAlerta(alerta) {
  if (alerta.tipo === 'vence_hoy') return 'Vence hoy'
  if (alerta.tipo === 'retraso') return `${alerta.dias_retraso} día${alerta.dias_retraso === 1 ? '' : 's'} de retraso`
  if (alerta.tipo === 'sin_fecha') return 'Sin fecha'
  return alerta.tipo === 'observado' ? 'Observado' : 'Rechazado'
}

function restablecerFiltros() {
  busquedaSc.value = ''
  busquedaItem.value = ''
  estado.value = null
  grupoCosto.value = null
  cargar({ reiniciar: true })
}

function aplicarFiltros() {
  cargar({ reiniciar: true })
}

function cambiarPagina(event) {
  first.value = event.first
  rows.value = event.rows
  cargar()
}

onMounted(async () => {
  try {
    await cargarCatalogos()
    await cargar()
  } catch {
    error.value = 'La consulta pública no está disponible en este momento.'
    loading.value = false
  }
})
</script>

<template>
  <main class="public-page">
    <header class="public-header">
      <div>
        <div class="public-brand"><span>SC</span> AppSC</div>
        <h1>Pedidos</h1>
        <p>Consulta pública permanente en modo solo lectura.</p>
      </div>
      <Tag value="Solo lectura" icon="pi pi-eye" severity="info" />
    </header>

    <section class="public-filtros" aria-label="Filtros de pedidos">
      <span class="p-input-icon-left">
        <i class="pi pi-search"></i>
        <InputText v-model="busquedaSc" placeholder="Buscar por N.° SC" @keydown.enter="aplicarFiltros" />
      </span>
      <span class="p-input-icon-left">
        <i class="pi pi-box"></i>
        <InputText v-model="busquedaItem" placeholder="Descripción o N.° parte" @keydown.enter="aplicarFiltros" />
      </span>
      <Select v-model="estado" :options="estados" option-label="label" option-value="value" placeholder="Todos los estados" show-clear @change="aplicarFiltros" />
      <Select v-model="grupoCosto" :options="gruposCosto" option-label="label" option-value="value" placeholder="Todos los grupos" show-clear @change="aplicarFiltros" />
      <Button label="Buscar" icon="pi pi-search" @click="aplicarFiltros" />
      <Button label="Restablecer" icon="pi pi-filter-slash" severity="secondary" outlined @click="restablecerFiltros" />
    </section>

    <Message v-if="error" severity="error" :closable="false">{{ error }}</Message>
    <Message v-if="errorAlertas && !error" severity="warn" :closable="false">{{ errorAlertas }}</Message>

    <section v-if="!loading && !error && !errorAlertas" class="public-alerts" aria-label="Alertas vigentes">
      <div class="public-alerts-title">
        <div><i class="pi pi-bell"></i><strong>Alertas vigentes</strong></div>
        <span>{{ alertas.length }} ítem{{ alertas.length === 1 ? '' : 's' }}</span>
      </div>
      <div v-if="alertas.length" class="public-alerts-list">
        <article v-for="alerta in alertas" :key="`${alerta.detalle_id}-${alerta.tipo}`" class="public-alert-row">
          <Tag :value="etiquetaAlerta(alerta)" :severity="alerta.tipo === 'rechazado' || alerta.tipo === 'retraso' || alerta.tipo === 'sin_fecha' ? 'danger' : 'warn'" />
          <strong>SC{{ alerta.nro_sc }}</strong>
          <span>{{ alerta.material || alerta.nro_parte || 'Ítem' }}</span>
          <span class="public-alert-state">{{ alerta.estado_actual }}</span>
          <span v-if="alerta.fecha_aprox_atencion">Fecha: {{ formatDate(alerta.fecha_aprox_atencion) }}</span>
        </article>
      </div>
      <p v-else class="public-no-alerts">No hay alertas vigentes con estos filtros.</p>
    </section>

    <template v-if="!error">
      <div v-if="loading" class="public-grid">
        <Skeleton v-for="n in 8" :key="n" height="170px" />
      </div>
      <template v-else>
        <p class="public-total">{{ totalTexto }}</p>
        <div v-if="pedidos.length" class="public-grid">
          <article v-for="pedido in pedidos" :key="pedido.pedido_id" class="public-card">
            <div class="public-card-head">
              <strong>SC{{ pedido.nro_sc }}</strong>
              <EstadoTag :nombre="pedido.estado_actual" size="sm" />
            </div>
            <p>{{ pedido.motivo || 'Sin motivo registrado' }}</p>
            <div class="public-card-meta">
              <span><i class="pi pi-calendar"></i> {{ formatDate(pedido.fecha_emision) }}</span>
              <span><i class="pi pi-list"></i> {{ formatQty(pedido.total_items) }} ítems</span>
              <span><i class="pi pi-box"></i> {{ etiquetaAtencion(pedido.estado_atencion) }}</span>
            </div>
            <div v-if="alertasPedido(pedido.pedido_id).length" class="public-card-alerts">
              <Tag
                v-for="alerta in alertasPedido(pedido.pedido_id).slice(0, 3)"
                :key="`${alerta.detalle_id}-${alerta.tipo}`"
                :value="etiquetaAlerta(alerta)"
                :severity="alerta.tipo === 'rechazado' || alerta.tipo === 'retraso' || alerta.tipo === 'sin_fecha' ? 'danger' : 'warn'"
                v-tooltip.top="`${alerta.material || alerta.nro_parte || 'Ítem'} · ${alerta.estado_actual}`"
              />
              <Tag v-if="alertasPedido(pedido.pedido_id).length > 3" :value="`+${alertasPedido(pedido.pedido_id).length - 3}`" severity="secondary" />
            </div>
            <div class="public-card-foot">
              <span v-if="pedido.grupo_costo" class="public-group">{{ pedido.grupo_costo }}</span>
              <Button label="Resumen" icon="pi pi-envelope" text size="small" @click.stop="abrirResumen(pedido)" />
            </div>
          </article>
        </div>
        <div v-else class="public-empty"><i class="pi pi-search"></i><p>No hay pedidos que coincidan con los filtros.</p></div>
        <Paginator v-if="total > rows" :first="first" :rows="rows" :total-records="total" :rows-per-page-options="[12, 24, 48]" @page="cambiarPagina" />
      </template>
    </template>
  </main>

  <PedidoResumenDialog
    v-model:visible="resumenVisible"
    :pedido="pedidoSeleccionado"
    :items="resumenItems"
    :estado-pedido="pedidoSeleccionado?.estado_actual"
    :datos-complementarios="false"
  />
</template>

<style scoped>
.public-page { min-height: 100vh; padding: 32px clamp(18px, 5vw, 72px); background: #f5f8fa; }
.public-header { display: flex; justify-content: space-between; align-items: flex-start; gap: 20px; max-width: 1360px; margin: 0 auto 22px; }
.public-brand { color: #3b6e8f; font-weight: 700; letter-spacing: .04em; }
.public-brand span { display: inline-grid; place-items: center; width: 27px; height: 27px; margin-right: 7px; border-radius: 7px; color: white; background: #3b6e8f; font-size: 11px; }
h1 { margin: 12px 0 4px; color: #1e2a38; font-size: clamp(24px, 4vw, 34px); }
.public-header p, .public-total { color: #64748b; }
.public-filtros { display: flex; flex-wrap: wrap; align-items: center; gap: 10px; max-width: 1360px; margin: 0 auto 18px; padding: 14px; border: 1px solid #dce6ec; border-radius: 12px; background: #fff; }
.public-filtros .p-input-icon-left { flex: 1 1 210px; }
.public-filtros :deep(.p-inputtext), .public-filtros :deep(.p-select) { width: 100%; }
.public-filtros > :deep(.p-select) { flex: 1 1 180px; }
.public-total { max-width: 1360px; margin: 0 auto 12px; font-size: 13px; }
.public-alerts { max-width: 1360px; margin: 0 auto 18px; padding: 14px; border: 1px solid #dce6ec; border-radius: 12px; background: white; }
.public-alerts-title { display: flex; justify-content: space-between; align-items: center; color: #475569; font-size: 12px; }
.public-alerts-title > div { display: flex; align-items: center; gap: 8px; color: #1e2a38; font-size: 14px; }
.public-alerts-title i { color: #e8a33d; }
.public-alerts-list { display: grid; grid-template-columns: repeat(auto-fill, minmax(290px, 1fr)); gap: 7px; margin-top: 10px; }
.public-alert-row { display: flex; align-items: center; flex-wrap: wrap; gap: 7px; padding: 8px; border-radius: 8px; background: #f7f9fb; color: #64748b; font-size: 11px; }
.public-alert-row strong { color: #315b76; }
.public-alert-state { font-weight: 600; }
.public-no-alerts { margin: 12px 0 2px; color: #718096; font-size: 12px; }
.public-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(270px, 1fr)); gap: 14px; max-width: 1360px; margin: 0 auto; }
.public-card { min-height: 170px; padding: 16px; border: 1px solid #dce6ec; border-radius: 12px; background: white; text-align: left; }
.public-card-head, .public-card-foot { display: flex; justify-content: space-between; align-items: center; gap: 10px; color: #1e2a38; }
.public-card p { min-height: 38px; margin: 12px 0; color: #475569; font-size: 13px; line-height: 1.45; }
.public-card-meta { display: flex; flex-wrap: wrap; gap: 8px 12px; color: #64748b; font-size: 12px; }
.public-card-meta i { margin-right: 4px; color: #3b6e8f; }
.public-card-alerts { display: flex; flex-wrap: wrap; gap: 5px; margin-top: 10px; }
.public-card-foot { margin-top: 10px; }
.public-group { color: #315b76; font-size: 11px; font-weight: 600; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.public-empty { display: grid; place-items: center; gap: 8px; min-height: 220px; color: #718096; }
.public-empty i { font-size: 28px; color: #b9c8d4; }
.public-page :deep(.p-paginator) { max-width: 1360px; margin: 18px auto 0; border: 1px solid #dce6ec; border-radius: 10px; background: #fff; }
@media (max-width: 600px) { .public-header { flex-direction: column; } .public-filtros > * { flex-basis: 100% !important; } }
</style>
