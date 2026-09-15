<script setup>
import { computed, ref, watch } from 'vue'
import { storeToRefs } from 'pinia'
import { useEstadosStore } from '@/stores/estadosStore'
import { useDetallePedidoStore } from '@/stores/detallePedidoStore'
import { useToast } from 'primevue/usetoast'
import { formatQty, toISODate } from '@/utils/format'

const props = defineProps({
  pedido: { type: Object, default: null },
  items: { type: Array, default: () => [] },
  visible: { type: Boolean, default: false },
})
const emit = defineEmits(['update:visible', 'cambiado'])

const estadosStore = useEstadosStore()
const detalleStore = useDetallePedidoStore()
const toast = useToast()
const { detalleStates } = storeToRefs(estadosStore)

const estadoId = ref(null)
const fecha = ref(new Date())
const comentario = ref('')
const cantidadesAprobadas = ref({})
const saving = ref(false)

const estadoSeleccionado = computed(() => estadosStore.byId(estadoId.value))
const esAprobado = computed(() => estadoSeleccionado.value?.nombre === 'Aprobado')
const estadoOptions = computed(() =>
  detalleStates.value.map((estado) => ({ label: estado.nombre, value: estado.estado_id })),
)
const itemsConMismoEstado = computed(() =>
  props.items.filter((item) => item.estado_actual_id === estadoId.value),
)
const cantidadesValidas = computed(() =>
  !esAprobado.value || props.items.every((item) => {
    const valor = cantidadesAprobadas.value[item.detalle_id]
    return valor !== null && valor !== '' && Number.isFinite(Number(valor)) && Number(valor) >= 0
  }),
)
const puedeGuardar = computed(() =>
  props.items.length > 0
  && estadoId.value
  && fecha.value
  && itemsConMismoEstado.value.length === 0
  && cantidadesValidas.value,
)

function descripcionItem(item) {
  return item.nro_parte || item.material || `Ítem #${item.detalle_id}`
}

watch(
  () => props.visible,
  (abierto) => {
    if (!abierto) return
    estadoId.value = null
    fecha.value = new Date()
    comentario.value = ''
    cantidadesAprobadas.value = Object.fromEntries(
      props.items.map((item) => [item.detalle_id, Number(item.cantidad_solicitada) || 0]),
    )
  },
)

async function guardar() {
  if (!puedeGuardar.value || !props.pedido) return
  saving.value = true
  try {
    const detalles = props.items.map((item) => ({
      detalle_id: item.detalle_id,
      ...(esAprobado.value ? { cantidad_aprobada: Number(cantidadesAprobadas.value[item.detalle_id]) } : {}),
    }))
    await detalleStore.cambiarEstadoItems({
      pedidoId: props.pedido.pedido_id,
      estadoId: estadoId.value,
      detalles,
      fecha: toISODate(fecha.value),
      comentario: comentario.value,
    })
    toast.add({
      severity: 'success',
      summary: 'Estados actualizados',
      detail: `${props.items.length} ítem${props.items.length === 1 ? '' : 's'} → ${estadoSeleccionado.value?.nombre}`,
      life: 4000,
    })
    emit('update:visible', false)
    emit('cambiado')
  } catch (error) {
    toast.add({ severity: 'error', summary: 'No se aplicaron cambios', detail: error.message, life: 6500 })
  } finally {
    saving.value = false
  }
}
</script>

<template>
  <Dialog
    :visible="visible"
    modal
    header="Cambiar estado de ítems seleccionados"
    :style="{ width: 'min(760px, 96vw)' }"
    :closable="!saving"
    @update:visible="emit('update:visible', $event)"
  >
    <div class="flex flex-column gap-4">
      <div class="seleccion-resumen">
        <strong>{{ items.length }} ítem{{ items.length === 1 ? '' : 's' }} seleccionado{{ items.length === 1 ? '' : 's' }}</strong>
        <span>El cambio se registrará de forma conjunta, conservando los demás ítems sin cambios.</span>
      </div>

      <div class="flex flex-column gap-2">
        <label class="field-label">Nuevo estado</label>
        <Select
          v-model="estadoId"
          :options="estadoOptions"
          option-label="label"
          option-value="value"
          placeholder="Seleccionar estado"
          fluid
        />
      </div>

      <Message v-if="itemsConMismoEstado.length" severity="warn" :closable="false">
        Quita de la selección {{ itemsConMismoEstado.length }} ítem{{ itemsConMismoEstado.length === 1 ? '' : 's' }} que ya {{ itemsConMismoEstado.length === 1 ? 'tiene' : 'tienen' }} este estado.
      </Message>

      <div v-if="esAprobado" class="flex flex-column gap-2">
        <label class="field-label">Cantidades aprobadas</label>
        <small class="hint">Se parte de la cantidad solicitada; puedes ajustarla para cada ítem.</small>
        <DataTable :value="items" data-key="detalle_id" size="small" class="tabla-aprobacion">
          <Column header="Ítem">
            <template #body="{ data }">
              <span class="item-name" :title="data.material">{{ descripcionItem(data) }}</span>
            </template>
          </Column>
          <Column header="Solic." style="width: 110px">
            <template #body="{ data }"><span class="mono">{{ formatQty(data.cantidad_solicitada) }}</span></template>
          </Column>
          <Column header="Aprob." style="width: 150px">
            <template #body="{ data }">
              <InputNumber
                v-model="cantidadesAprobadas[data.detalle_id]"
                mode="decimal"
                :min="0"
                :max-fraction-digits="2"
                fluid
              />
            </template>
          </Column>
        </DataTable>
      </div>

      <div class="flex flex-column gap-2">
        <label class="field-label">Fecha de registro</label>
        <DatePicker v-model="fecha" date-format="dd/mm/yy" fluid />
      </div>

      <div class="flex flex-column gap-2">
        <label class="field-label">Comentario (opcional)</label>
        <Textarea v-model="comentario" rows="2" auto-resize placeholder="Motivo compartido para los ítems seleccionados" />
      </div>
    </div>

    <template #footer>
      <Button label="Cancelar" text severity="secondary" :disabled="saving" @click="emit('update:visible', false)" />
      <Button
        :label="`Aplicar a ${items.length} ítem${items.length === 1 ? '' : 's'}`"
        icon="pi pi-check"
        :loading="saving"
        :disabled="!puedeGuardar"
        @click="guardar"
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

.seleccion-resumen {
  display: flex;
  flex-direction: column;
  gap: 3px;
  padding: 11px 13px;
  border-left: 3px solid var(--accent-500);
  border-radius: 0 8px 8px 0;
  background: #f7f9fb;
  font-size: 12.5px;
  color: var(--text-muted);
}

.seleccion-resumen strong { color: var(--text-strong); }
.hint { color: var(--text-muted); }
.item-name { font-size: 12.5px; }
.tabla-aprobacion { border: 1px solid var(--line); border-radius: 8px; overflow: hidden; }
</style>
