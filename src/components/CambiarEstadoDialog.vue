<script setup>
import { ref, computed, watch } from 'vue'
import { storeToRefs } from 'pinia'
import { useEstadosStore } from '@/stores/estadosStore'
import { useDetallePedidoStore } from '@/stores/detallePedidoStore'
import { useToast } from 'primevue/usetoast'
import { formatQty } from '@/utils/format'

const props = defineProps({
  item: { type: Object, default: null },
  visible: { type: Boolean, default: false },
})
const emit = defineEmits(['update:visible', 'cambiado'])

const estadosStore = useEstadosStore()
const detalleStore = useDetallePedidoStore()
const toast = useToast()

const { detalleStates } = storeToRefs(estadosStore)

const estadoId = ref(null)
const cantidadAprobada = ref(0)
const comentario = ref('')
const saving = ref(false)

const estadoOptions = computed(() =>
  detalleStates.value.map((e) => ({
    label: e.nombre,
    value: e.estado_id,
    disabled: opcionDisabled({ value: e.estado_id }),
  })),
)

const esAprobado = computed(
  () => estadosStore.byId(estadoId.value)?.nombre === 'Aprobado',
)

const esMismoEstado = computed(
  () => props.item && estadoId.value === props.item.estado_actual_id,
)

const estadoActualNombre = computed(() => props.item?.estados_catalogo?.nombre ?? '—')

const itemAprobado = computed(() =>
  ['Aprobado', 'En cotización'].includes(props.item?.estados_catalogo?.nombre),
)
const estadoEnCompraId = computed(() => estadosStore.byName('En compra')?.estado_id)

function opcionDisabled(option) {
  return option.value === estadoEnCompraId.value && !itemAprobado.value
}

const motivoEnCompra = computed(() =>
  itemAprobado.value ? '' : 'Requiere ítem aprobado.',
)

watch(
  () => props.visible,
  (v) => {
    if (v && props.item) {
      estadoId.value = props.item.estado_actual_id
      cantidadAprobada.value = Number(props.item.cantidad_aprobada) || Number(props.item.cantidad_solicitada)
      comentario.value = ''
    }
  },
)

async function guardar() {
  if (!props.item || !estadoId.value || esMismoEstado.value) return
  saving.value = true
  try {
    if (esAprobado.value) {
      await detalleStore.aprobarItem(
        props.item.detalle_id,
        estadoId.value,
        cantidadAprobada.value,
        comentario.value || null,
      )
      toast.add({
        severity: 'success',
        summary: 'Ítem aprobado',
        detail: `Cantidad aprobada: ${formatQty(cantidadAprobada.value)}`,
        life: 4000,
      })
    } else {
      await detalleStore.cambiarEstadoItem(
        props.item.detalle_id,
        estadoId.value,
        comentario.value || null,
      )
      toast.add({
        severity: 'success',
        summary: 'Estado actualizado',
        detail: estadosStore.byId(estadoId.value)?.nombre,
        life: 4000,
      })
    }
    emit('update:visible', false)
    emit('cambiado')
  } catch (e) {
    toast.add({ severity: 'error', summary: 'Error', detail: e.message, life: 6000 })
  } finally {
    saving.value = false
  }
}
</script>

<template>
  <Dialog
    :visible="visible"
    modal
    header="Cambiar estado del ítem"
    :style="{ width: '460px' }"
    :closable="!saving"
    @update:visible="emit('update:visible', $event)"
  >
    <div v-if="item" class="flex flex-column gap-4">
      <div class="item-resumen">
        <div class="mono item-resumen-id">{{ item.nro_parte || 'Sin nro parte' }}</div>
        <div class="item-resumen-mat">{{ item.material || 'Sin descripción' }}</div>
      </div>

      <div class="transicion">
        <span class="field-label">Estado actual</span>
        <div class="flex align-items-center gap-2">
          <EstadoTag :nombre="estadoActualNombre" size="sm" />
          <i class="pi pi-arrow-right transicion-flecha" aria-hidden="true"></i>
          <EstadoTag v-if="estadoId" :nombre="estadosStore.byId(estadoId)?.nombre" size="sm" />
          <span v-else class="transicion-placeholder">nuevo estado</span>
        </div>
      </div>

      <div class="flex flex-column gap-2">
        <label class="field-label">Nuevo estado</label>
        <Select
          v-model="estadoId"
          :options="estadoOptions"
          option-label="label"
          option-value="value"
          :option-disabled="opcionDisabled"
          fluid
        />
        <small v-if="estadoEnCompraId && !itemAprobado" style="color: var(--text-muted)">
          "En compra" requiere que el ítem esté aprobado.
        </small>
      </div>

      <div v-if="esAprobado" class="flex flex-column gap-2">
        <label class="field-label">Cantidad aprobada</label>
        <InputNumber
          v-model="cantidadAprobada"
          mode="decimal"
          :min="0"
          :max-fraction-digits="2"
          fluid
        />
        <small style="color: var(--text-muted)">
          Solicitada: {{ formatQty(item.cantidad_solicitada) }}
        </small>
      </div>

      <div class="flex flex-column gap-2">
        <label class="field-label">Comentario (opcional)</label>
        <Textarea v-model="comentario" rows="2" auto-resize placeholder="Motivo del cambio" />
      </div>
    </div>

    <template #footer>
      <Button label="Cancelar" text severity="secondary" :disabled="saving" @click="emit('update:visible', false)" />
      <Button label="Aplicar estado" icon="pi pi-check" :loading="saving" :disabled="!estadoId || esMismoEstado" @click="guardar" />
    </template>
  </Dialog>
</template>

<style scoped>
.field-label {
  font-size: 11px;
  font-weight: 700;
  text-transform: uppercase;
  letter-spacing: 0.08em;
  color: var(--text-muted);
}

.transicion {
  display: flex;
  flex-direction: column;
  gap: 6px;
  background: #f7f9fb;
  border: 1px solid var(--line);
  border-radius: 8px;
  padding: 10px 12px;
}

.transicion-flecha {
  font-size: 12px;
  color: var(--text-muted);
}

.transicion-placeholder {
  font-size: 12px;
  color: #b3c0cd;
  font-style: italic;
}

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
</style>
