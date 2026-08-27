<script setup>
import { ref, computed, watch } from 'vue'
import { useDetallePedidoStore } from '@/stores/detallePedidoStore'
import { useToast } from 'primevue/usetoast'
import { formatQty, toISODate } from '@/utils/format'

const props = defineProps({
  item: { type: Object, default: null },
  visible: { type: Boolean, default: false },
})
const emit = defineEmits(['update:visible', 'registrado'])

const detalleStore = useDetallePedidoStore()
const toast = useToast()

const cantidad = ref(0)
const fecha = ref(new Date())
const documento = ref('')
const saving = ref(false)

const aprobada = computed(() => Number(props.item?.cantidad_aprobada ?? 0))
const atendida = computed(() => Number(props.item?.cantidad_atendida ?? 0))
const pendiente = computed(() => Math.max(aprobada.value - atendida.value, 0))
const sinAprobacion = computed(() => aprobada.value <= 0)
const estadosAprobados = ['Aprobado', 'En cotización', 'En compra', 'Atendido']
const aprobado = computed(() => estadosAprobados.includes(props.item?.estados_catalogo?.nombre))

watch(
  () => props.visible,
  (v) => {
    if (v && props.item) {
      cantidad.value = pendiente.value
      fecha.value = new Date()
      documento.value = ''
    }
  },
)

async function registrar() {
  if (!props.item || !aprobado.value || Number(cantidad.value) <= 0) return
  if (Number(cantidad.value) > pendiente.value) {
    toast.add({
      severity: 'warn',
      summary: 'Cantidad no válida',
      detail: `La cantidad no puede superar lo pendiente (${formatQty(pendiente.value)}).`,
      life: 5000,
    })
    return
  }
  saving.value = true
  try {
    await detalleStore.registrarIngreso(props.item.detalle_id, cantidad.value, toISODate(fecha.value), documento.value)
    toast.add({
      severity: 'success',
      summary: 'Ingreso registrado',
      detail: `${formatQty(cantidad.value)} unidades para ${props.item.nro_parte || props.item.material || 'el ítem'}`,
      life: 4000,
    })
    emit('update:visible', false)
    emit('registrado')
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
    header="Registrar ingreso (entrega)"
    :style="{ width: '440px' }"
    :closable="!saving"
    @update:visible="emit('update:visible', $event)"
  >
    <div v-if="item" class="flex flex-column gap-4">
      <div class="item-resumen">
        <div class="mono item-resumen-id">{{ item.nro_parte || 'Sin nro parte' }}</div>
        <div class="item-resumen-mat">{{ item.material || 'Sin descripción' }}</div>
      </div>

      <Message v-if="!aprobado" severity="warn" :closable="false">
        El ítem no está aprobado. No se puede registrar ingreso.
      </Message>

      <Message v-if="aprobado && sinAprobacion" severity="warn" :closable="false">
        El ítem no tiene cantidad aprobada. No se puede registrar ingreso.
      </Message>

      <div class="resumen-grid">
        <div class="resumen-cell">
          <span class="resumen-label">Aprobada</span>
          <span class="resumen-value">{{ formatQty(aprobada) }}</span>
        </div>
        <div class="resumen-cell">
          <span class="resumen-label">Atendida</span>
          <span class="resumen-value">{{ formatQty(atendida) }}</span>
        </div>
        <div class="resumen-cell">
          <span class="resumen-label">Pendiente</span>
          <span class="resumen-value" style="color: var(--accent-500)">{{ formatQty(pendiente) }}</span>
        </div>
      </div>

      <div class="flex flex-column gap-2">
        <label class="field-label">Fecha de entrega</label>
        <DatePicker v-model="fecha" date-format="dd/mm/yy" fluid />
        <small style="color: var(--text-muted)">
          Selecciona la fecha del ingreso.
        </small>
      </div>

      <div class="flex flex-column gap-2">
        <label class="field-label">Documento referencia</label>
        <InputText v-model="documento" maxlength="25" placeholder="Guía / factura" class="mono" fluid />
      </div>

      <div class="flex flex-column gap-2">
        <label class="field-label">Cantidad a ingresar</label>
        <InputNumber
          v-model="cantidad"
          mode="decimal"
          :min="0"
          :max="pendiente"
          :max-fraction-digits="2"
          fluid
          autofocus
        />
        <small style="color: var(--text-muted)">
          Máximo a ingresar: {{ formatQty(pendiente) }} (lo que queda pendiente).
        </small>
      </div>
    </div>

    <template #footer>
      <Button label="Cancelar" text severity="secondary" :disabled="saving" @click="emit('update:visible', false)" />
      <Button
        label="Registrar ingreso"
        icon="pi pi-plus"
        :loading="saving"
        :disabled="Number(cantidad) <= 0 || !aprobado"
        @click="registrar"
      />
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

.resumen-grid {
  display: grid;
  grid-template-columns: repeat(3, 1fr);
  gap: 8px;
}

.resumen-cell {
  display: flex;
  flex-direction: column;
  gap: 3px;
  background: #f7f9fb;
  border: 1px solid var(--line);
  border-radius: 8px;
  padding: 9px 12px;
}

.resumen-label {
  font-size: 10px;
  font-weight: 700;
  text-transform: uppercase;
  letter-spacing: 0.07em;
  color: var(--text-muted);
}

.resumen-value {
  font-size: 16px;
  font-weight: 700;
  color: var(--text-strong);
  font-variant-numeric: tabular-nums;
}
</style>
