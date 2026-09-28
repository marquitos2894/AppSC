<script setup>
import { ref, watch } from 'vue'
import { storeToRefs } from 'pinia'
import { usePedidosStore } from '@/stores/pedidosStore'
import { useDetallePedidoStore } from '@/stores/detallePedidoStore'
import { useFiltroGlobalStore } from '@/stores/filtroGlobalStore'
import { useAuthStore } from '@/stores/authStore'
import { formatQty, formatDate } from '@/utils/format'
import { estiloGrupoCosto } from '@/utils/grupoCosto'

const emit = defineEmits(['nuevo', 'eliminar', 'editar', 'cambiar-estado', 'historial', 'generar-resumen'])

const pedidosStore = usePedidosStore()
const detalleStore = useDetallePedidoStore()
const filtroGlobalStore = useFiltroGlobalStore()
const auth = useAuthStore()

const { pedidos, loading, total } = storeToRefs(pedidosStore)

const layout = ref('grid')
const first = ref(0)
const rows = ref(12)

watch(
  () => `${pedidosStore.busqueda}|${pedidosStore.busquedaItems}|${pedidosStore.filtroEstado}|${filtroGlobalStore.grupoCosto}`,
  () => {
    first.value = 0
  },
)

function abrirDetalle(pedido) {
  detalleStore.abrir(pedido.pedido_id)
}

function contador(items) {
  return formatQty(items)
}

function claseAtencionPedido(valor) {
  return { PENDIENTE: 'sin-atender', PARCIAL: 'parcial', COMPLETO: 'completa' }[valor] || ''
}

function etiquetaAtencionPedido(valor) {
  return { PENDIENTE: 'Pendiente', PARCIAL: 'Parcial', COMPLETO: 'Completo' }[valor] || ''
}

function etiquetaGrupoCosto(pedido) {
  return pedido.grupo_costo || 'Sin grupo de costo'
}

function alertasPedido(pedido, tipo) {
  return pedidosStore.alertas.filter((alerta) =>
    Number(alerta.pedido_id) === Number(pedido.pedido_id) && (!tipo || alerta.tipo === tipo),
  )
}

function cantidadItemsAtendidos(pedido) {
  return pedidosStore.itemsEstado.filter((item) =>
    Number(item.pedido_id) === Number(pedido.pedido_id)
      && item.estados_catalogo?.nombre === 'Atendido',
  ).length
}

function etiquetaVenceHoy(pedido) {
  const cantidad = alertasPedido(pedido, 'vence_hoy').length
  return cantidad > 1 ? `Vence hoy · ${cantidad}` : 'Vence hoy'
}

function etiquetaRetraso(pedido) {
  const maxDias = Math.max(...alertasPedido(pedido, 'retraso').map((alerta) => Number(alerta.dias_retraso) || 0))
  return `${maxDias} día${maxDias === 1 ? '' : 's'} de retraso`
}

function tooltipExcepcion(pedido, tipo) {
  const coincidencias = alertasPedido(pedido, tipo)
  const items = [...new Set(coincidencias.map((alerta) => alerta.material || alerta.nro_parte).filter(Boolean))]
  const titulo = tipo === 'observado' ? 'Ítems observados' : 'Ítems rechazados'
  if (!items.length) return `${titulo}: ${tipo === 'observado' ? pedido.items_observados : pedido.items_rechazados}`
  const visibles = items.slice(0, 8)
  if (items.length > visibles.length) visibles.push(`+${items.length - visibles.length} más`)
  return `${titulo}:\n${visibles.join('\n')}`
}

function puedeCambiarEstado(pedido) {
  return auth.canWrite && !pedido.paso_por_analisis
}

function puedeEditar(pedido) { return auth.canWrite && !pedido.paso_por_analisis }

function abrirCambioEstado(evento, pedido) {
  if (!puedeCambiarEstado(pedido)) return
  evento.stopPropagation()
  emit('cambiar-estado', pedido)
}
</script>

<template>
  <div class="pedidos-card">
    <DataView
      :value="pedidos"
      :layout="layout"
      v-model:first="first"
      :rows="rows"
      paginator
      :rows-per-page-options="[12, 24, 48]"
      :total-records="total"
      :always-show-paginator="false">
      <template #header>
        <div class="dataview-toolbar">
          <span class="flex align-items-center gap-2" style="font-size: 12.5px; color: var(--text-muted)">
            <i class="pi pi-list"></i>
            {{ total }} pedidos
          </span>

          <div class="layout-toggle" role="group" aria-label="Cambiar vista">
            <button
              type="button"
              class="layout-toggle-btn"
              :class="{ active: layout === 'grid' }"
              aria-label="Vista cuadrícula"
              @click="layout = 'grid'">
              <i class="pi pi-th-large"></i>
            </button>
            <button
              type="button"
              class="layout-toggle-btn"
              :class="{ active: layout === 'list' }"
              aria-label="Vista lista"
              @click="layout = 'list'">
              <i class="pi pi-list"></i>
            </button>
          </div>
        </div>
      </template>

      <template #list="{ items }">
        <div v-if="loading" class="dataview-list-skeleton">
          <div v-for="n in 6" :key="n" class="flex align-items-center gap-3 p-3">
            <Skeleton width="70px" height="16px" />
            <Skeleton width="110px" height="16px" />
            <Skeleton style="flex: 1" height="16px" />
            <Skeleton width="130px" height="22px" />
          </div>
        </div>

        <div v-else class="dataview-list">
          <div
            v-for="pedido in items"
            :key="pedido.pedido_id"
            class="pedido-row"
            role="button"
            tabindex="0"
            @click="abrirDetalle(pedido)"
            @keydown.enter="abrirDetalle(pedido)"
          >
            <span class="cell-id">SC{{ pedido.nro_sc }}</span>

            <!-- span class="pedido-row-nrosc mono" :title="pedido.nro_sc">
              {{ pedido.nro_sc || '—' }}
            </span -->

            <span class="pedido-row-fecha">{{ formatDate(pedido.fecha_emision) }}</span>

            <span class="grupo-costo-badge" :style="estiloGrupoCosto(pedido.grupo_costo)" :title="etiquetaGrupoCosto(pedido)">
              <i class="pi pi-tag" aria-hidden="true"></i>
              {{ etiquetaGrupoCosto(pedido) }}
            </span>

            <div class="cell-motivo" :title="pedido.motivo">
              <template v-if="pedido.motivo">{{ pedido.motivo }}</template>
              <span v-else class="cell-motivo-empty">Sin motivo</span>
            </div>

            <EstadoTag
              :nombre="pedido.estado_actual"
              :class="puedeCambiarEstado(pedido) ? 'estado-tag--clickable' : 'estado-tag--locked'"
              :tabindex="puedeCambiarEstado(pedido) ? 0 : undefined"
              :role="puedeCambiarEstado(pedido) ? 'button' : undefined"
              v-tooltip.top="puedeCambiarEstado(pedido) ? 'Cambiar estado' : 'Ya no editable (pasó por En análisis)'"
              @click="abrirCambioEstado($event, pedido)"
              @keydown.enter="abrirCambioEstado($event, pedido)"
            />

            <span
              v-if="pedido.estado_atencion"
              class="atencion-badge"
              :class="claseAtencionPedido(pedido.estado_atencion)"
            >
              {{ etiquetaAtencionPedido(pedido.estado_atencion) }}
            </span>

            <span class="pedido-row-items mono" :title="`${contador(pedido.total_items)} ítems`">
              {{ contador(pedido.total_items) }}
            </span>

            <div class="pedido-status-alertas">
              <Tag v-if="alertasPedido(pedido, 'vence_hoy').length" :value="etiquetaVenceHoy(pedido)" icon="pi pi-clock" severity="warn" />
              <Tag v-if="alertasPedido(pedido, 'retraso').length" :value="etiquetaRetraso(pedido)" icon="pi pi-exclamation-circle" severity="danger" />
              <Tag v-if="pedido.items_observados > 0" :value="`Observados · ${contador(pedido.items_observados)}`" icon="pi pi-eye" severity="warn" v-tooltip.top="tooltipExcepcion(pedido, 'observado')" />
              <Tag v-if="pedido.items_rechazados > 0" :value="`Rechazados · ${contador(pedido.items_rechazados)}`" icon="pi pi-ban" severity="danger" v-tooltip.top="tooltipExcepcion(pedido, 'rechazado')" />
              <Tag v-if="cantidadItemsAtendidos(pedido) > 0" :value="`Atendidos · ${contador(cantidadItemsAtendidos(pedido))}`" icon="pi pi-check" severity="success" />
            </div>

            <div class="item-acciones">
              <Button
                icon="pi pi-file-edit"
                text
                rounded
                size="small"
                aria-label="Generar resumen"
                v-tooltip.top="'Generar resumen para correo'"
                @click.stop="emit('generar-resumen', pedido)"
              />
              <Button
                v-if="puedeEditar(pedido)"
                icon="pi pi-pen-to-square"
                text rounded size="small" aria-label="Editar pedido"
                v-tooltip.top="'Editar pedido'"
                @click.stop="emit('editar', pedido)"
              />
              <Button
                v-if="auth.canWrite"
                icon="pi pi-trash"
                text
                rounded
                size="small"
                severity="danger"
                aria-label="Eliminar pedido"
                v-tooltip.top="'Eliminar pedido'"
                @click.stop="emit('eliminar', pedido)"
              />
            </div>
          </div>
        </div>
      </template>

      <template #grid="{ items }">
        <div v-if="loading" class="dataview-grid">
          <div v-for="n in 6" :key="n" class="pedido-card-grid">
            <Skeleton height="18px" width="60%" />
            <Skeleton height="40px" width="100%" />
            <Skeleton height="14px" width="40%" />
          </div>
        </div>

        <div v-else class="dataview-grid">
          <div
            v-for="pedido in items"
            :key="pedido.pedido_id"
            class="pedido-card-grid"
            role="button"
            tabindex="0"
            @click="abrirDetalle(pedido)"
            @keydown.enter="abrirDetalle(pedido)"
          >
            <div class="pedido-card-grid-head">
              <span class="cell-id">SC{{ pedido.nro_sc }}</span>
              <EstadoTag
                :nombre="pedido.estado_actual"
                size="sm"
                :class="puedeCambiarEstado(pedido) ? 'estado-tag--clickable' : 'estado-tag--locked'"
                :tabindex="puedeCambiarEstado(pedido) ? 0 : undefined"
                :role="puedeCambiarEstado(pedido) ? 'button' : undefined"
                v-tooltip.top="puedeCambiarEstado(pedido) ? 'Cambiar estado' : 'Ya no editable (pasó por En análisis)'"
                @click="abrirCambioEstado($event, pedido)"
                @keydown.enter="abrirCambioEstado($event, pedido)"
              />
            </div>

           

            <div class="pedido-card-grid-motivo" :title="pedido.motivo">
              <template v-if="pedido.motivo">{{ pedido.motivo }}</template>
              <span v-else class="cell-motivo-empty">Sin motivo</span>
            </div>

            <div class="pedido-card-grid-meta">
              <span class="pedido-row-fecha">{{ formatDate(pedido.fecha_emision) }}</span>
              <span class="mono">{{ contador(pedido.total_items) }} ítems</span>
            </div>

            <span class="grupo-costo-badge" :style="estiloGrupoCosto(pedido.grupo_costo)" :title="etiquetaGrupoCosto(pedido)">
              <i class="pi pi-tag" aria-hidden="true"></i>
              {{ etiquetaGrupoCosto(pedido) }}
            </span>

            <span
              v-if="pedido.estado_atencion"
              class="atencion-badge"
              :class="claseAtencionPedido(pedido.estado_atencion)"
            >
              {{ etiquetaAtencionPedido(pedido.estado_atencion) }}
            </span>

            <div class="pedido-card-grid-foot">
              <div class="pedido-status-alertas">
                <Tag v-if="alertasPedido(pedido, 'vence_hoy').length" :value="etiquetaVenceHoy(pedido)" icon="pi pi-clock" severity="warn" />
                <Tag v-if="alertasPedido(pedido, 'retraso').length" :value="etiquetaRetraso(pedido)" icon="pi pi-exclamation-circle" severity="danger" />
                <Tag v-if="pedido.items_observados > 0" :value="`Observados · ${contador(pedido.items_observados)}`" icon="pi pi-eye" severity="warn" v-tooltip.top="tooltipExcepcion(pedido, 'observado')" />
                <Tag v-if="pedido.items_rechazados > 0" :value="`Rechazados · ${contador(pedido.items_rechazados)}`" icon="pi pi-ban" severity="danger" v-tooltip.top="tooltipExcepcion(pedido, 'rechazado')" />
                <Tag v-if="cantidadItemsAtendidos(pedido) > 0" :value="`Atendidos · ${contador(cantidadItemsAtendidos(pedido))}`" icon="pi pi-check" severity="success" />
              </div>

              <div class="item-acciones">
                <Button
                  icon="pi pi-file-edit"
                  text
                  rounded
                  size="small"
                  aria-label="Generar resumen"
                  v-tooltip.top="'Generar resumen para correo'"
                  @click.stop="emit('generar-resumen', pedido)"
                />
                <Button
                  v-if="puedeEditar(pedido)"
                  icon="pi pi-pen-to-square"
                  text rounded size="small" aria-label="Editar pedido"
                  v-tooltip.top="'Editar pedido'"
                  @click.stop="emit('editar', pedido)"
                />
                <Button
                  icon="pi pi-history"
                  text
                  rounded
                  size="small"
                  aria-label="Historial"
                  v-tooltip.top="'Historial'"
                  @click.stop="emit('historial', pedido)"
                />
                <Button
                  v-if="auth.canWrite"
                  icon="pi pi-trash"
                  text
                  rounded
                  size="small"
                  severity="danger"
                  aria-label="Eliminar pedido"
                  v-tooltip.top="'Eliminar pedido'"
                  @click.stop="emit('eliminar', pedido)"
                />
              </div>
            </div>
          </div>
        </div>
      </template>

      <template #empty>
        <div class="empty-state">
          <i class="pi pi-inbox"></i>
          <p>No hay pedidos que coincidan.</p>
          <Button
            v-if="auth.canWrite && !pedidos.length && !pedidosStore.busqueda && !pedidosStore.filtroEstado"
            label="Crear el primer pedido"
            size="small"
            icon="pi pi-plus"
            @click="emit('nuevo')"
          />
        </div>
      </template>
    </DataView>
  </div>
</template>
