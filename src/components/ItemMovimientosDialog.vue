<script setup>
import { ref, computed, watch } from 'vue'
import { storeToRefs } from 'pinia'
import { useDetallePedidoStore } from '@/stores/detallePedidoStore'
import { useConfirm } from 'primevue/useconfirm'
import { useToast } from 'primevue/usetoast'
import { formatQty, formatDate, toISODate, toLocalDate } from '@/utils/format'


const props = defineProps({
  item: { type: Object, default: null },
  visible: { type: Boolean, default: false },
})
const emit = defineEmits(['update:visible'])

const detalleStore = useDetallePedidoStore()
const confirm = useConfirm()
const toast = useToast()

const { historialPorItem, ingresosPorItem, loadingMapa } = storeToRefs(detalleStore)

const historial = computed(() =>
  props.item ? historialPorItem.value[props.item.detalle_id] ?? [] : [],
)
const ingresos = computed(() =>
  props.item ? ingresosPorItem.value[props.item.detalle_id] ?? [] : [],
)
const cargando = computed(() => {
  if (!props.item) return false
  return Boolean(loadingMapa.value[`hist-${props.item.detalle_id}`] || loadingMapa.value[`ing-${props.item.detalle_id}`])
})

const ediciones = ref({})

watch(
  () => props.visible,
  async (v) => {
    if (v && props.item) {
      ediciones.value = {}
      try {
        await Promise.all([
          detalleStore.fetchHistorialItem(props.item.detalle_id),
          detalleStore.fetchIngresos(props.item.detalle_id),
        ])
      } catch (e) {
        toast.add({ severity: 'error', summary: 'Error', detail: e.message, life: 6000 })
      }
    }
  },

  console.log(ingresosPorItem)
)

function limiteFila(ing) {
  const aprobada = Number(props.item?.cantidad_aprobada ?? 0)
  const atendida = Number(props.item?.cantidad_atendida ?? 0)
  return Math.max(aprobada - (atendida - Number(ing.cantidad ?? 0)), 0)
}

function activarEdicion(ing) {
  ediciones.value[ing.ingreso_id] = {
    cantidad: Number(ing.cantidad ?? 0),
    fecha: toLocalDate(ing.fecha) ?? new Date(),
    documento: ing.documento || '',
    dirty: false,
  }
}

function marcarDirty(id) {
  if (ediciones.value[id]) ediciones.value[id].dirty = true
}

function esDirty(ing) {
  const e = ediciones.value[ing.ingreso_id]
  if (!e) return false
  return e.dirty
}

async function guardarEdicion(ing) {
  const e = ediciones.value[ing.ingreso_id]
  if (!e || !e.dirty) return
  if (Number(e.cantidad) > limiteFila(ing)) {
    toast.add({
      severity: 'warn',
      summary: 'Cantidad no válida',
      detail: `La cantidad no puede superar ${formatQty(limiteFila(ing))} para este ingreso.`,
      life: 5000,
    })
    return
  }
  try {
    await detalleStore.editarIngreso(ing.ingreso_id, {
      cantidad: e.cantidad,
      fecha: toISODate(e.fecha),
      documento: e.documento,
    })
    toast.add({ severity: 'success', summary: 'Entrega actualizada', life: 3000 })
    ediciones.value[ing.ingreso_id] = undefined
    await recargar()
  } catch (err) {
    toast.add({ severity: 'error', summary: 'Error', detail: err.message, life: 6000 })
  }
}

function confirmarEliminar(ing) {
  confirm.require({
    message: `¿Eliminar la entrega de ${formatQty(ing.cantidad)} (${ing.documento || 'sin documento'})? Se revertirá el estado si el ítem queda sin entregas.`,
    header: 'Eliminar entrega',
    icon: 'pi pi-trash',
    rejectLabel: 'Cancelar',
    acceptLabel: 'Eliminar',
    acceptProps: { severity: 'danger' },
    accept: async () => {
      try {
        await detalleStore.eliminarIngreso(ing.ingreso_id)
        toast.add({ severity: 'success', summary: 'Entrega eliminada', life: 3000 })
        await recargar()
      } catch (e) {
        toast.add({ severity: 'error', summary: 'Error', detail: e.message, life: 6000 })
      }
    },
  })
}

async function recargar() {
  try {
    await Promise.all([
      detalleStore.fetchHistorialItem(props.item.detalle_id),
      detalleStore.fetchIngresos(props.item.detalle_id),
    ])
  } catch (e) {
    toast.add({ severity: 'error', summary: 'Error', detail: e.message, life: 6000 })
  }
}
</script>

<template>
  <Dialog
    :visible="visible"
    modal
    header="Movimientos del ítem"
    :style="{ width: '620px' }"
    @update:visible="emit('update:visible', $event)"
  >
    <div v-if="item" class="flex flex-column gap-4">
      <div class="item-resumen">
        <div class="mono item-resumen-id">{{ item.nro_parte || 'Sin nro parte' }}</div>
        <div class="item-resumen-mat">{{ item.material || 'Sin descripción' }}</div>
      </div>

      <div v-if="cargando" class="flex flex-column gap-2">
        <Skeleton width="100%" height="30px" />
        <Skeleton width="70%" height="14px" />
        <Skeleton width="85%" height="14px" />
      </div>
      
      <template v-else>
        <div class="flex flex-column gap-2">
          <h4 class="section-subtitle">Entregas ({{ ingresos.length }})</h4>
          <div v-if="ingresos.length" class="ingresos-table">
            <div class="ingreso-row ingreso-row--head">
              <span>Fecha</span>
              <span>Cantidad</span>
              <span>Documento</span>
              <span>Comentario</span>
              <span class="ta-right">Acciones</span>
            </div>

            <div v-for="ing in ingresos" :key="ing.ingreso_id" class="ingreso-row ingreso-row--editable">
              <template v-if="ediciones[ing.ingreso_id]">
               
                <DatePicker
                  v-model="ediciones[ing.ingreso_id].fecha"
                  date-format="dd/mm/yy"
                  size="small"
                  @update:model-value="marcarDirty(ing.ingreso_id)"
                />
                <InputNumber
                  v-model="ediciones[ing.ingreso_id].cantidad"
                  mode="decimal"
                  :min="0"
                  :max="limiteFila(ing)"
                  :max-fraction-digits="2"
                  size="small"
                  @update:model-value="marcarDirty(ing.ingreso_id)"
                />
                <InputText
                  v-model="ediciones[ing.ingreso_id].documento"
                  maxlength="25"
                  size="small"
                  @update:model-value="marcarDirty(ing.ingreso_id)"
                />
                <div class="ingreso-acciones">
                  <Button
                    icon="pi pi-check"
                    text
                    rounded
                    size="small"
                    aria-label="Guardar"
                    v-tooltip.top="'Guardar'"
                    :disabled="!esDirty(ing)"
                    @click="guardarEdicion(ing)"
                  />
                  <Button
                    icon="pi pi-times"
                    text
                    rounded
                    size="small"
                    severity="secondary"
                    aria-label="Cancelar edición"
                    v-tooltip.top="'Cancelar'"
                    @click="ediciones[ing.ingreso_id] = undefined"
                  />
                  <Button
                    icon="pi pi-trash"
                    text
                    rounded
                    size="small"
                    severity="danger"
                    aria-label="Eliminar"
                    v-tooltip.top="'Eliminar'"
                    @click="confirmarEliminar(ing)"
                  />
                </div>
              </template>

              <template v-else>
                <span class="mono ingreso-fecha">{{ formatDate(ing.fecha) }}</span>
                <span class="mono">{{ formatQty(ing.cantidad) }}</span>
                <span class="mono ingreso-doc" :class="{ 'ingreso-doc--vacio': !ing.documento }">
                  {{ ing.documento || '—' }}
                </span>
                <span class="ingreso-comentario" :class="{ 'ingreso-doc--vacio': !ing.comentario }" :title="ing.comentario">
                  {{ ing.comentario || '—' }}
                </span>
                <div class="ingreso-acciones">
                  <Button
                    icon="pi pi-pencil"
                    text
                    rounded
                    size="small"
                    aria-label="Editar"
                    v-tooltip.top="'Editar'"
                    @click="activarEdicion(ing)"
                  />
                  <Button
                    icon="pi pi-trash"
                    text
                    rounded
                    size="small"
                    severity="danger"
                    aria-label="Eliminar"
                    v-tooltip.top="'Eliminar'"
                    @click="confirmarEliminar(ing)"
                  />
                </div>
              </template>
            </div>
          </div>
          <p v-else class="hist-item-comment empty" style="margin: 0">Sin entregas registradas.</p>
        </div>

        <div class="flex flex-column gap-2">
          <h4 class="section-subtitle">Historial de estados</h4>
          <HistorialTimeline :eventos="historial" />
        </div>
      </template>
    </div>
  </Dialog>
</template>

<style scoped>
.item-resumen {
  background: #f7f9fb;
  border-left: 3px solid var(--accent-500);
  border-radius: 0 8px 8px 0;
  padding: 10px 12px;
}

.item-resumen-id {
  font-weight: 600;
  color: var(--text-strong);
  font-size: 13px;
}

.item-resumen-mat {
  font-size: 12.5px;
  color: var(--text);
  margin-top: 3px;
}

.section-subtitle {
  margin: 0;
  font-size: 11px;
  font-weight: 700;
  text-transform: uppercase;
  letter-spacing: 0.09em;
  color: var(--text-muted);
}

.ingresos-table {
  border: 1px solid var(--line);
  border-radius: 8px;
  overflow: hidden;
}

.ingreso-row {
  display: flex;
  align-items: center;
  gap: 10px;
  padding: 7px 12px;
  border-bottom: 1px solid #edf1f5;
  font-size: 13px;
}

.ingreso-row:last-child {
  border-bottom: 0;
}

.ingreso-row--head {
  background: #fbfcfd;
  font-size: 10.5px;
  font-weight: 700;
  text-transform: uppercase;
  letter-spacing: 0.07em;
  color: #5b6b7d;
}

.ingreso-row--editable > span,
.ingreso-row--head > span {
  flex: 1;
  min-width: 0;
}

.ingreso-row--editable :deep(.p-datepicker),
.ingreso-row--editable :deep(.p-inputnumber),
.ingreso-row--editable :deep(.p-inputtext) {
  flex: 1;
  min-width: 0;
}

.ingreso-fecha {
  font-size: 12px;
  color: var(--text);
}

.ingreso-doc {
  font-size: 12px;
  color: var(--text);
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.ingreso-comentario {
  flex: 1;
  min-width: 0;
  color: var(--text);
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.ingreso-doc--vacio {
  color: #b3c0cd;
}

.ingreso-acciones {
  display: flex;
  gap: 2px;
  justify-content: flex-end;
  flex: 0 0 auto;
}

.ta-right {
  text-align: right;
  font-variant-numeric: tabular-nums;
}
</style>
