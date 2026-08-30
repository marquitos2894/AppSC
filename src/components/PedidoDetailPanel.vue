<script setup>
import { ref, watch } from 'vue'
import { storeToRefs } from 'pinia'
import { useDetallePedidoStore } from '@/stores/detallePedidoStore'
import { useAuthStore } from '@/stores/authStore'
import { useConfirm } from 'primevue/useconfirm'
import { useToast } from 'primevue/usetoast'
import { formatQty, formatDate, toLocalDate, toISODate } from '@/utils/format'

const detalleStore = useDetallePedidoStore()
const auth = useAuthStore()
const confirm = useConfirm()
const toast = useToast()

const { visible, pedido, items, historialPedido, loading, estadoPedido } = storeToRefs(detalleStore)

const dialogEstado = ref(false)
const dialogIngreso = ref(false)
const dialogMovimientos = ref(false)
const itemSeleccionado = ref(null)
const aprobadaEdit = ref({})

watch(
  items,
  (nuevos) => {
    const mapa = {}
    for (const it of nuevos ?? []) mapa[it.detalle_id] = Number(it.cantidad_aprobada ?? 0)
    aprobadaEdit.value = mapa
  },
  { immediate: true },
)

function claseAtencion(valor) {
  return {
    'sin-atender': valor === 'SIN_ATENDER',
    parcial: valor === 'PARCIAL',
    completa: valor === 'COMPLETA',
  }
}

function abrirEstado(item) {
  if (esAtendido(item) || auth.isReadOnly) return
  itemSeleccionado.value = item
  dialogEstado.value = true
}

function esAtendido(item) {
  return item?.estados_catalogo?.nombre === 'Atendido'
}

function clickEstado(item) {
  if (!esAtendido(item)) abrirEstado(item)
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

async function guardarFechaAprox(item, d) {
  try {
    await detalleStore.actualizarFechaAprox(item.detalle_id, toISODate(d))
    toast.add({ severity: 'success', summary: 'Fecha aprox. actualizada', life: 3000 })
  } catch (e) {
    toast.add({ severity: 'error', summary: 'Error', detail: e.message, life: 6000 })
  }
}

async function commitAprobada(item) {
  const nuevo = Number(aprobadaEdit.value[item.detalle_id] ?? 0)
  if (nuevo === Number(item.cantidad_aprobada ?? 0)) return
  try {
    await detalleStore.editarCantidadAprobada(item.detalle_id, nuevo)
    toast.add({ severity: 'success', summary: 'Aprobación ajustada', life: 3000 })
  } catch (e) {
    toast.add({ severity: 'error', summary: 'Error', detail: e.message, life: 6000 })
  }
}
</script>

<template>
  <Drawer
    v-model:visible="visible"
    position="right"
    header="Detalle del pedido"
    style="width: min(1200px, 100vw)"
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
            <span class="detalle-id">{{ pedido.nro_sc }}</span>
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

            <Column header="Aprob." header-class="columna-aprobada" style="width: 90px">
              <template #body="{ data }">
                <InputNumber
                  v-model="aprobadaEdit[data.detalle_id]"
                  mode="decimal"
                  :min="0"
                  :max-fraction-digits="2"
                  size="small"
                  style="width: 72px"
                  class="columna-aprobada"
                  :disabled="auth.isReadOnly"
                  @blur="commitAprobada(data)"
                />
              </template>
            </Column>

            <Column header="Atend." header-class="columna-atendida" style="width: 70px">
              <template #body="{ data }">
                <span class="cell-num columna-atendida">{{ formatQty(data.cantidad_atendida) }}</span>
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
                  <EstadoTag
                    :nombre="data.estados_catalogo?.nombre"
                    size="sm"
                    v-tooltip.top="esAtendido(data) ? 'No editable (Atendido)' : 'Cambiar estado'"
                    :class="esAtendido(data) || auth.isReadOnly ? 'estado-tag--locked' : 'estado-tag--clickable'"
                    @click="clickEstado(data)"
                  />
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
            <Column header="F. aprox." style="width: 150px">
              <template #body="{ data }">
                <div class="flex align-items-center gap-1">
                  <DatePicker
                    :model-value="toLocalDate(data.fecha_aprox_atencion)"
                    date-format="dd/mm/yy"
                    show-icon
                    size="small"
                    :disabled="auth.isReadOnly"
                    @date-select="(d) => guardarFechaAprox(data, d)"
                  />
                  <Button
                    v-if="auth.canWrite && data.fecha_aprox_atencion"
                    icon="pi pi-times"
                    text
                    rounded
                    size="small"
                    severity="secondary"
                    aria-label="Quitar fecha"
                    v-tooltip.top="'Quitar fecha'"
                    @click="guardarFechaAprox(data, null)"
                  />
                </div>
              </template>
            </Column>

            <Column header="" style="width: 100px">
              <template #body="{ data }">
                <div class="item-acciones">
                  <Button
                    v-if="auth.canWrite"
                    icon="pi pi-plus"
                    text
                    rounded
                    size="small"
                    aria-label="Registrar Atencion"
                    v-tooltip.top="'Registrar Atencion'"
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
                    v-if="auth.canWrite"
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

        <!--div class="detalle-section">
          <h3 class="detalle-section-title">Historial del pedido</h3>
          <HistorialTimeline :eventos="historialPedido" />
        </div -->
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
