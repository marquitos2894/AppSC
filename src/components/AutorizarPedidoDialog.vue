<script setup>
import { ref, watch } from 'vue'
import { usePedidosStore } from '@/stores/pedidosStore'
import { useToast } from 'primevue/usetoast'

const props = defineProps({
  pedido: { type: Object, default: null },
  visible: { type: Boolean, default: false },
})
const emit = defineEmits(['update:visible', 'autorizado'])

const pedidosStore = usePedidosStore()
const toast = useToast()

const fecha = ref(new Date())
const saving = ref(false)

watch(
  () => props.visible,
  (v) => {
    if (v && props.pedido) {
      fecha.value = props.pedido.autorizado ? new Date(props.pedido.autorizado) : new Date()
    }
  },
)

async function guardar() {
  if (!props.pedido || !fecha.value) return
  saving.value = true
  try {
    await pedidosStore.autorizarPedido(props.pedido.pedido_id, fecha.value.toISOString())
    toast.add({ severity: 'success', summary: 'Pedido autorizado', life: 4000 })
    emit('update:visible', false)
    emit('autorizado')
  } catch (e) {
    toast.add({ severity: 'error', summary: 'Error', detail: e.message, life: 6000 })
  } finally {
    saving.value = false
  }
}

async function quitar() {
  if (!props.pedido) return
  saving.value = true
  try {
    await pedidosStore.autorizarPedido(props.pedido.pedido_id, null)
    toast.add({ severity: 'success', summary: 'Autorización quitada', life: 4000 })
    emit('update:visible', false)
    emit('autorizado')
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
    header="Autorizar pedido"
    :style="{ width: '440px' }"
    :closable="!saving"
    @update:visible="emit('update:visible', $event)"
  >
    <div v-if="pedido" class="flex flex-column gap-4">
      <div class="item-resumen">
        <div class="flex align-items-center gap-2">
          <span class="cell-id" style="font-size: 14px">SC{{ pedido.nro_sc }}</span>
        </div>
        <div class="item-resumen-mat" :title="pedido.motivo">
          {{ pedido.motivo || 'Sin motivo' }}
        </div>
      </div>

      <div class="flex flex-column gap-2">
        <label class="field-label">Fecha de autorización</label>
        <DatePicker v-model="fecha" show-time date-format="dd/mm/yy" fluid />
        <small style="color: var(--text-muted)">
          Sella la fecha y hora en que se autoriza el pedido.
        </small>
      </div>
    </div>

    <template #footer>
      <Button
        v-if="pedido && pedido.autorizado"
        label="Quitar autorización"
        text
        severity="danger"
        :disabled="saving"
        @click="quitar"
      />
      <Button label="Cancelar" text severity="secondary" :disabled="saving" @click="emit('update:visible', false)" />
      <Button label="Autorizar" icon="pi pi-lock-open" :loading="saving" @click="guardar" />
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
