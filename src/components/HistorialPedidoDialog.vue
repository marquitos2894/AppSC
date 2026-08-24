<script setup>
import { computed, watch } from 'vue'
import { storeToRefs } from 'pinia'
import { useDetallePedidoStore } from '@/stores/detallePedidoStore'
import { useToast } from 'primevue/usetoast'

const props = defineProps({
  pedido: { type: Object, default: null },
  visible: { type: Boolean, default: false },
})
const emit = defineEmits(['update:visible'])

const detalleStore = useDetallePedidoStore()
const toast = useToast()

const { historialPedido, loadingMapa } = storeToRefs(detalleStore)

const cargando = computed(() => Boolean(loadingMapa.value.histPedido))

watch(
  () => props.visible,
  async (v) => {
    if (v && props.pedido) {
      try {
        await detalleStore.cargarHistorial(props.pedido.pedido_id)
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
    header="Historial del pedido"
    :style="{ width: '560px' }"
    @update:visible="emit('update:visible', $event)"
  >
    <div v-if="pedido" class="flex flex-column gap-3">
      <div class="item-resumen">
        <div class="flex align-items-center gap-2">
          <span class="cell-id" style="font-size: 14px">{{ pedido.pedido_id }}</span>
          <EstadoTag :nombre="pedido.estado_actual" size="sm" />
        </div>
        <div class="item-resumen-mat" :title="pedido.motivo">
          {{ pedido.motivo || 'Sin motivo' }}
        </div>
      </div>

      <div v-if="cargando" class="flex flex-column gap-2">
        <Skeleton width="100%" height="36px" />
        <Skeleton width="80%" height="36px" />
        <Skeleton width="60%" height="36px" />
      </div>

      <HistorialTimeline v-else :eventos="historialPedido" />
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

.item-resumen-mat {
  font-size: 12.5px;
  color: var(--text);
  margin-top: 4px;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
</style>
