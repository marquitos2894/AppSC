<script setup>
import { computed } from 'vue'
import { estadoColor } from '@/stores/estadosStore'
import { formatDate } from '@/utils/format'

const props = defineProps({
  eventos: { type: Array, default: () => [] },
})

const items = computed(() =>
  props.eventos.map((e) => {
    const nombre = e.estados_catalogo?.nombre ?? '—'
    return {
      key: e.historial_id,
      nombre,
      fecha: formatDate(e.fecha, true),
      comentario: e.comentario,
      color: estadoColor(nombre),
    }
  }),
)
</script>

<template>
  <Timeline v-if="items.length" :value="items" layout="vertical" align="left">
    <template #content="{ item }">
      <div class="hist-item">
        <div class="hist-item-head">
          <EstadoTag :nombre="item.nombre" size="sm" />
          <span class="hist-item-date">{{ item.fecha }}</span>
        </div>
        <p class="hist-item-comment" :class="{ empty: !item.comentario }">
          {{ item.comentario || 'Sin comentario' }}
        </p>
      </div>
    </template>
    <template #marker="{ item }">
      <span
        class="timeline-dot"
        :style="{ backgroundColor: item.color }"
        aria-hidden="true"
      ></span>
    </template>
  </Timeline>
  <p v-else class="hist-item-comment empty">Sin movimientos registrados.</p>
</template>

<style scoped>
.timeline-dot {
  width: 12px;
  height: 12px;
  border-radius: 50%;
  display: inline-block;
  border: 2px solid #fff;
  box-shadow: 0 0 0 2px #dde4eb;
}
</style>
