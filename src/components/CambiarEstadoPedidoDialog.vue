<script setup>
import { ref, watch, computed } from 'vue'
import { storeToRefs } from 'pinia'
import { supabase } from '@/api/supabaseClient'
import { useEstadosStore } from '@/stores/estadosStore'
import { useToast } from 'primevue/usetoast'

const props = defineProps({
  pedido: { type: Object, default: null },
  visible: { type: Boolean, default: false },
})
const emit = defineEmits(['update:visible', 'cambiado'])

const estadosStore = useEstadosStore()
const toast = useToast()

const { pedidoStates } = storeToRefs(estadosStore)

const estadoId = ref(null)
const fecha = ref(new Date())
const comentario = ref('')
const saving = ref(false)

const estadoOptions = computed(() =>
  pedidoStates.value.map((e) => ({ label: e.nombre, value: e.estado_id })),
)

const esMismoEstado = computed(
  () => props.pedido && estadoId.value === props.pedido.estado_actual_id,
)

const pasoPorAnalisis = computed(() => props.pedido?.paso_por_analisis === true)

watch(
  () => props.visible,
  (v) => {
    if (v && props.pedido) {
      estadoId.value = null
      fecha.value = new Date()
      comentario.value = ''
    }
  },
)

async function guardar() {
  if (!props.pedido || !estadoId.value || esMismoEstado.value || pasoPorAnalisis.value) return
  saving.value = true
  try {
    const { error } = await supabase.rpc('fn_cambiar_estado_pedido', {
      p_pedido_id: props.pedido.pedido_id,
      p_estado_id: estadoId.value,
      p_fecha: fecha.value.toISOString(),
      p_comentario: comentario.value || null,
    })
    if (error) throw error
    const nombre = estadosStore.byId(estadoId.value)?.nombre
    toast.add({
      severity: 'success',
      summary: 'Estado actualizado',
      detail: `Pedido #${props.pedido.pedido_id} → ${nombre}`,
      life: 4000,
    })
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
    header="Cambiar estado del pedido"
    :style="{ width: '480px' }"
    :closable="!saving"
    @update:visible="emit('update:visible', $event)"
  >
    <div v-if="pedido" class="flex flex-column gap-4">
      <Message v-if="pasoPorAnalisis" severity="warn" :closable="false">
        Este pedido ya registró "En análisis" y su estado ya no puede editarse manualmente.
      </Message>

      <div class="item-resumen">
        <div class="flex align-items-center gap-2">
          <span class="cell-id" style="font-size: 14px">{{ pedido.nro_sc }}</span>
          <EstadoTag :nombre="pedido.estado_actual" size="sm" />
        </div>
        <div class="item-resumen-mat" :title="pedido.motivo">
          {{ pedido.motivo || 'Sin motivo' }}
        </div>
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

      <div class="flex flex-column gap-2">
        <label class="field-label">Fecha de registro</label>
        <DatePicker v-model="fecha" show-time date-format="dd/mm/yy" fluid />
        <small style="color: var(--text-muted)">
          Por defecto la fecha y hora actuales. Se aplica al pedido y a todos sus ítems.
        </small>
      </div>

      <div class="flex flex-column gap-2">
        <label class="field-label">Comentario</label>
        <Textarea v-model="comentario" rows="2" auto-resize placeholder="Motivo del cambio de estado" />
      </div>
    </div>

    <template #footer>
      <Button label="Cancelar" text severity="secondary" :disabled="saving" @click="emit('update:visible', false)" />
      <Button
        label="Guardar"
        icon="pi pi-check"
        :loading="saving"
        :disabled="!estadoId || esMismoEstado || pasoPorAnalisis"
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

.item-resumen {
  background: #f7f9fb;
  border-left: 3px solid var(--accent-500);
  border-radius: 0 8px 8px 0;
  padding: 10px 12px;
}

.item-resumen-mat {
  font-size: 12.5px;
  color: var(--text);
  margin-top: 4px;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
</style>
