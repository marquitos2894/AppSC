<script setup>
import { ref, watch } from 'vue'
import { storeToRefs } from 'pinia'
import { usePedidosStore } from '@/stores/pedidosStore'
import { useDetallePedidoStore } from '@/stores/detallePedidoStore'
import { useFiltroGlobalStore } from '@/stores/filtroGlobalStore'
import { useAuthStore } from '@/stores/authStore'
import { formatQty, formatDate } from '@/utils/format'

const emit = defineEmits(['nuevo', 'eliminar', 'cambiar-estado', 'historial', 'autorizar', 'generar-resumen'])

const pedidosStore = usePedidosStore()
const detalleStore = useDetallePedidoStore()
const filtroGlobalStore = useFiltroGlobalStore()
const auth = useAuthStore()

const { pedidos, loading, total } = storeToRefs(pedidosStore)

const layout = ref('grid')
const first = ref(0)
const rows = ref(12)

watch(
  () => `${pedidosStore.busqueda}|${pedidosStore.filtroEstado}|${filtroGlobalStore.grupoCosto}`,
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

function hayExcepciones(pedido) {
  return pedido.items_observados > 0 || pedido.items_rechazados > 0
}

function autorizacion(pedido) {
  return pedido.autorizado ? `Autorizado ${formatDate(pedido.autorizado, true)}` : 'Sin autorización'
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

            <span class="grupo-costo-badge" :title="etiquetaGrupoCosto(pedido)">
              <i class="pi pi-tag" aria-hidden="true"></i>
              {{ etiquetaGrupoCosto(pedido) }}
            </span>

            <div class="cell-motivo" :title="pedido.motivo">
              <template v-if="pedido.motivo">{{ pedido.motivo }}</template>
              <span v-else class="cell-motivo-empty">Sin motivo</span>
            </div>

            <EstadoTag :nombre="pedido.estado_actual" />

            <span
              class="auth-badge"
              :class="pedido.autorizado ? 'auth-ok' : 'auth-none'"
              :title="autorizacion(pedido)"
            >
              <i :class="pedido.autorizado ? 'pi pi-lock' : 'pi pi-lock-open'"></i>
              {{ pedido.autorizado ? 'Autorizado' : 'Sin autorización' }}
            </span>

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

            <div class="pedido-row-excepciones">
              <span v-if="pedido.items_observados > 0" class="counter-badge observado">
                {{ contador(pedido.items_observados) }} obs
              </span>
              <span v-if="pedido.items_rechazados > 0" class="counter-badge rechazado">
                {{ contador(pedido.items_rechazados) }} rech
              </span>
              <span v-if="!hayExcepciones(pedido)" class="counter-badge none">—</span>
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
                v-if="auth.canWrite"
                icon="pi pi-lock-open"
                text
                rounded
                size="small"
                aria-label="Autorizar"
                v-tooltip.top="'Autorizar'"
                @click.stop="emit('autorizar', pedido)"
              />
 
              <Button
                v-if="auth.canWrite"
                icon="pi pi-pencil"
                text
                rounded
                size="small"
                aria-label="Cambiar estado"
                v-tooltip.top="pedido.paso_por_analisis ? 'Ya no editable (pasó por En análisis)' : 'Cambiar estado'"
                :disabled="pedido.paso_por_analisis"
                @click.stop="emit('cambiar-estado', pedido)"
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
              <EstadoTag :nombre="pedido.estado_actual" size="sm" />
            </div>

           

            <div class="pedido-card-grid-motivo" :title="pedido.motivo">
              <template v-if="pedido.motivo">{{ pedido.motivo }}</template>
              <span v-else class="cell-motivo-empty">Sin motivo</span>
            </div>

            <div class="pedido-card-grid-meta">
              <span class="pedido-row-fecha">{{ formatDate(pedido.fecha_emision) }}</span>
              <span class="mono">{{ contador(pedido.total_items) }} ítems</span>
            </div>

            <span class="grupo-costo-badge" :title="etiquetaGrupoCosto(pedido)">
              <i class="pi pi-tag" aria-hidden="true"></i>
              {{ etiquetaGrupoCosto(pedido) }}
            </span>

            <span
              class="auth-badge"
              :class="pedido.autorizado ? 'auth-ok' : 'auth-none'"
              :title="autorizacion(pedido)"
            >
              <i :class="pedido.autorizado ? 'pi pi-lock' : 'pi pi-lock-open'"></i>
              {{ pedido.autorizado ? 'Autorizado' : 'Sin autorización' }}
            </span>

            <span
              v-if="pedido.estado_atencion"
              class="atencion-badge"
              :class="claseAtencionPedido(pedido.estado_atencion)"
            >
              {{ etiquetaAtencionPedido(pedido.estado_atencion) }}
            </span>

            <div class="pedido-card-grid-foot">
              <div class="pedido-row-excepciones">
                <span v-if="pedido.items_observados > 0" class="counter-badge observado">
                  {{ contador(pedido.items_observados) }} obs
                </span>
                <span v-if="pedido.items_rechazados > 0" class="counter-badge rechazado">
                  {{ contador(pedido.items_rechazados) }} rech
                </span>
                <span v-if="!hayExcepciones(pedido)" class="counter-badge none">—</span>
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
                  v-if="auth.canWrite"
                  icon="pi pi-lock-open"
                  text
                  rounded
                  size="small"
                  aria-label="Autorizar"
                  v-tooltip.top="'Autorizar'"
                  @click.stop="emit('autorizar', pedido)"
                />
                <Button
                  v-if="auth.canWrite"
                  icon="pi pi-pencil"
                  text
                  rounded
                  size="small"
                  aria-label="Cambiar estado"
                  :disabled="pedido.estado_actual === 'En análisis'"
                  v-tooltip.top="pedido.estado_actual === 'En análisis' ? 'Bloqueado en En análisis' : 'Cambiar estado'"
                  @click.stop="emit('cambiar-estado', pedido)"
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
