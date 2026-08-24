<script setup>
import { ref } from 'vue'
import { storeToRefs } from 'pinia'
import { useDetallePedidoStore } from '@/stores/detallePedidoStore'
import { useConfirm } from 'primevue/useconfirm'
import { useToast } from 'primevue/usetoast'
import { formatQty, formatDate } from '@/utils/format'

const detalleStore = useDetallePedidoStore()
const confirm = useConfirm()
const toast = useToast()

const { visible, pedido, items, historialPedido, loading, estadoPedido } = storeToRefs(detalleStore)

const dialogEstado = ref(false)
const dialogIngreso = ref(false)
const dialogMovimientos = ref(false)
const itemSeleccionado = ref(null)

function claseAtencion(valor) {
  return {
    'sin-atender': valor === 'SIN_ATENDER',
    parcial: valor === 'PARCIAL',
    completa: valor === 'COMPLETA',
  }
}

function abrirEstado(item) {
  itemSeleccionado.value = item
  dialogEstado.value = true
}

function abrirIngreso(item) {
  itemSeleccionado.value = item
  dialogIngreso.value = true
}

function abrirMovimientos(item) {
  itemSeleccionado.value = item
  dialogMovimientos.value = true
}

function confirmarEliminarItem(item) {
  confirm.require({
    message: `¿Eliminar el ítem "${item.nro_parte || item.material || 'sin descripción'}"? Se aplicará borrado lógico.`,
    header: 'Eliminar ítem',
    icon: 'pi pi-trash',
    rejectLabel: 'Cancelar',
    acceptLabel: 'Eliminar',
    acceptProps: { severity: 'danger' },
    accept: async () => {
      try {
        await detalleStore.eliminarItem(item.detalle_id)
        toast.add({ severity: 'success', summary: 'Ítem eliminado', life: 3000 })
      } catch (e) {
        toast.add({ severity: 'error', summary: 'Error', detail: e.message, life: 6000 })
      }
    },
  })
}

function pendiente(item) {
  return detalleStore.pendiente(item)
}
</script>

<template>
  <Drawer
    v-model:visible="visible"
    position="right"
    header="Detalle del pedido"
    style="width: min(820px, 100vw)"
    @hide="detalleStore.cerrar()"
  >
    <div class="detalle-sidebar">
      <template v-if="loading && !pedido">
        <div class="flex flex-column gap-3">
          <Skeleton width="220px" height="28px" />
          <Skeleton width="100%" height="90px" />
          <Skeleton width="100%" height="220px" />
        </div>
      </template>

      <template v-else-if="pedido">
        <div class="detalle-header">
          <div class="detalle-id-block">
            <span class="detalle-id">{{ pedido.pedido_id }}</span>
            <EstadoTag :nombre="estadoPedido" />
          </div>

          <div class="detalle-meta">
            <div v-if="pedido.nro_sc" class="meta-line">
              <span class="meta-label">N° SC</span>
              <span class="mono">{{ pedido.nro_sc }}</span>
            </div>
            <div class="meta-line">
              <span class="meta-label">Emisión</span>
              <span>{{ formatDate(pedido.fecha_emision) }}</span>
            </div>
            <div v-if="pedido.grupo_costo" class="meta-line">
              <span class="meta-label">G. costo</span>
              <span>{{ pedido.grupo_costo }}</span>
            </div>
          </div>

          <div v-if="pedido.motivo" class="detalle-motivo">{{ pedido.motivo }}</div>
        </div>

        <div class="detalle-section">
          <h3 class="detalle-section-title">Flujo del pedido</h3>
          <EstadoStepper :estado-nombre="estadoPedido" />
        </div>

        <div class="detalle-section">
          <h3 class="detalle-section-title">
            Ítems
            <span class="mono" style="color: var(--text-muted); font-size: 11px; text-transform: none; letter-spacing: 0">
              {{ items.length }}
            </span>
          </h3>

          <DataTable :value="items" data-key="detalle_id" table-style="min-width: 680px">
            <Column header="Nro parte" style="width: 110px">
              <template #body="{ data }">
                <span class="mono cell-num" style="font-size: 12.5px">{{ data.nro_parte || '—' }}</span>
              </template>
            </Column>

            <Column header="Material" style="min-width: 170px">
              <template #body="{ data }">
                <span style="font-size: 12.5px">{{ data.material || '—' }}</span>
              </template>
            </Column>

            <Column header="Solic." style="width: 70px">
              <template #body="{ data }">
                <span class="cell-num">{{ formatQty(data.cantidad_solicitada) }}</span>
              </template>
            </Column>

            <Column header="Aprob." style="width: 70px">
              <template #body="{ data }">
                <span class="cell-num">{{ formatQty(data.cantidad_aprobada) }}</span>
              </template>
            </Column>

            <Column header="Atend." style="width: 70px">
              <template #body="{ data }">
                <span class="cell-num">{{ formatQty(data.cantidad_atendida) }}</span>
              </template>
            </Column>

            <Column header="Pend." style="width: 70px">
              <template #body="{ data }">
                <span
                  class="pend-cell cell-num"
                  :class="pendiente(data) > 0 ? 'pend-positivo' : 'pend-cero'"
                >
                  {{ formatQty(pendiente(data)) }}
                </span>
              </template>
            </Column>

            <Column header="Estado" style="width: 150px">
              <template #body="{ data }">
                <div class="flex flex-column gap-1">
                  <EstadoTag :nombre="data.estados_catalogo?.nombre" size="sm" />
                  <span
                    v-if="data.estado_atencion"
                    class="atencion-badge"
                    :class="claseAtencion(data.estado_atencion)"
                  >
                    {{ data.estado_atencion }}
                  </span>
                </div>
              </template>
            </Column>

            <Column header="" style="width: 130px">
              <template #body="{ data }">
                <div class="item-acciones">
                  <Button
                    icon="pi pi-pencil"
                    text
                    rounded
                    size="small"
                    aria-label="Cambiar estado"
                    v-tooltip.top="'Cambiar estado'"
                    @click="abrirEstado(data)"
                  />
                  <Button
                    icon="pi pi-plus"
                    text
                    rounded
                    size="small"
                    aria-label="Registrar ingreso"
                    v-tooltip.top="'Registrar ingreso'"
                    @click="abrirIngreso(data)"
                  />
                  <Button
                    icon="pi pi-history"
                    text
                    rounded
                    size="small"
                    aria-label="Movimientos"
                    v-tooltip.top="'Movimientos'"
                    @click="abrirMovimientos(data)"
                  />
                  <Button
                    icon="pi pi-trash"
                    text
                    rounded
                    size="small"
                    severity="danger"
                    aria-label="Eliminar ítem"
                    v-tooltip.top="'Eliminar ítem'"
                    @click="confirmarEliminarItem(data)"
                  />
                </div>
              </template>
            </Column>
          </DataTable>
        </div>

        <div class="detalle-section">
          <h3 class="detalle-section-title">Historial del pedido</h3>
          <HistorialTimeline :eventos="historialPedido" />
        </div>
      </template>

      <div v-else class="empty-state">
        <i class="pi pi-exclamation-circle"></i>
        <p>No se pudo cargar el pedido.</p>
      </div>
    </div>
  </Drawer>

  <CambiarEstadoDialog v-model:visible="dialogEstado" :item="itemSeleccionado" />
  <IngresoForm v-model:visible="dialogIngreso" :item="itemSeleccionado" />
  <ItemMovimientosDialog v-model:visible="dialogMovimientos" :item="itemSeleccionado" />
</template>
