<script setup>
import { computed, ref, watch } from 'vue'
import { useDetallePedidoStore } from '@/stores/detallePedidoStore'
import { useToast } from 'primevue/usetoast'
import { formatDate, toISODate } from '@/utils/format'

const props = defineProps({
  visible: Boolean,
  pedido: { type: Object, default: null },
  items: { type: Array, default: () => [] },
})
const emit = defineEmits(['update:visible', 'actualizado'])
const detalleStore = useDetallePedidoStore()
const toast = useToast()
const fecha = ref(null)
const comentario = ref('')
const saving = ref(false)
const textoAccion = computed(() => fecha.value ? 'Asignar fecha' : 'Quitar fecha')

watch(() => props.visible, (abierto) => {
  if (abierto) {
    fecha.value = null
    comentario.value = ''
  }
})

async function guardar() {
  if (!props.pedido || !props.items.length) return
  saving.value = true
  try {
    await detalleStore.actualizarFechaAproxItems({
      pedidoId: props.pedido.pedido_id,
      detalleIds: props.items.map((item) => item.detalle_id),
      fecha: toISODate(fecha.value),
      comentario: comentario.value,
    })
    toast.add({ severity: 'success', summary: 'Fechas estimadas actualizadas', detail: `${props.items.length} ítems actualizados.`, life: 3500 })
    emit('update:visible', false)
    emit('actualizado')
  } catch (error) {
    toast.add({ severity: 'error', summary: 'No se actualizaron las fechas', detail: error.message, life: 6000 })
  } finally {
    saving.value = false
  }
}
</script>

<template>
  <Dialog :visible="visible" modal header="Asignar fecha aproximada" :style="{ width: 'min(680px, 96vw)' }" :closable="!saving" @update:visible="emit('update:visible', $event)">
    <div class="flex flex-column gap-4">
      <Message severity="info" :closable="false">
        Esta fecha es una estimación, no registra una entrega. El cambio quedará auditado por ítem.
      </Message>
      <div class="fecha-grid">
        <div class="flex flex-column gap-2">
          <label class="field-label">Fecha aproximada</label>
          <DatePicker v-model="fecha" date-format="dd/mm/yy" show-icon fluid />
          <small>Déjala vacía para quitar la fecha de los ítems seleccionados.</small>
        </div>
        <div class="flex flex-column gap-2">
          <label class="field-label">Comentario de planificación</label>
          <Textarea v-model="comentario" rows="2" auto-resize placeholder="Motivo o referencia opcional" />
        </div>
      </div>
      <div class="items-lista">
        <strong>{{ items.length }} ítem{{ items.length === 1 ? '' : 's' }} seleccionado{{ items.length === 1 ? '' : 's' }}</strong>
        <div v-for="item in items" :key="item.detalle_id" class="item-linea">
          <span class="mono">{{ item.nro_parte || '—' }}</span>
          <span>{{ item.material || 'Sin descripción' }}</span>
          <span class="fecha-anterior">Actual: {{ item.fecha_aprox_atencion ? formatDate(item.fecha_aprox_atencion) : 'sin fecha' }}</span>
        </div>
      </div>
    </div>
    <template #footer>
      <Button label="Cancelar" text severity="secondary" :disabled="saving" @click="emit('update:visible', false)" />
      <Button :label="textoAccion" icon="pi pi-calendar" :loading="saving" @click="guardar" />
    </template>
  </Dialog>
</template>

<style scoped>
.fecha-grid { display: grid; grid-template-columns: 1fr 1.2fr; gap: 16px; }
.field-label { font-size: 11px; font-weight: 700; text-transform: uppercase; letter-spacing: .08em; color: var(--text-muted); }
small { color: var(--text-muted); }
.items-lista { border: 1px solid var(--line); border-radius: 8px; padding: 10px; max-height: 220px; overflow: auto; font-size: 12px; }
.item-linea { display: grid; grid-template-columns: 110px minmax(130px, 1fr) auto; gap: 8px; padding: 7px 2px; border-bottom: 1px solid var(--line); }
.item-linea:last-child { border-bottom: 0; }
.fecha-anterior { color: var(--text-muted); }
@media (max-width: 580px) { .fecha-grid { grid-template-columns: 1fr; } .item-linea { grid-template-columns: 1fr; gap: 2px; } }
</style>
