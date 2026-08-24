<script setup>
import { computed, watch } from 'vue'
import { storeToRefs } from 'pinia'
import { useDetallePedidoStore } from '@/stores/detallePedidoStore'
import { useToast } from 'primevue/usetoast'
import { formatQty, formatDate } from '@/utils/format'

const props = defineProps({
  item: { type: Object, default: null },
  visible: { type: Boolean, default: false },
})
const emit = defineEmits(['update:visible'])

const detalleStore = useDetallePedidoStore()
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

watch(
  () => props.visible,
  async (v) => {
    if (v && props.item) {
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
)
</script>

<template>
  <Dialog
    :visible="visible"
    modal
    header="Movimientos del ítem"
    :style="{ width: '560px' }"
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
              <span class="ta-right">Cantidad</span>
            </div>
            <div v-for="ing in ingresos" :key="ing.ingreso_id" class="ingreso-row">
              <span class="mono ingreso-fecha">{{ formatDate(ing.fecha, true) }}</span>
              <span class="ta-right mono">{{ formatQty(ing.cantidad) }}</span>
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
  justify-content: space-between;
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

.ingreso-fecha {
  font-size: 12px;
  color: var(--text);
}

.ta-right {
  text-align: right;
  font-variant-numeric: tabular-nums;
}
</style>
