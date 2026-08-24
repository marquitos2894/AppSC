<script setup>
import { computed } from 'vue'
import { storeToRefs } from 'pinia'
import { useEstadosStore } from '@/stores/estadosStore'

const props = defineProps({
  estadoNombre: { type: String, required: true },
})

const estadosStore = useEstadosStore()
const { flow } = storeToRefs(estadosStore)

const indiceDecision = computed(() => flow.value.findIndex((e) => e.nombre === 'En análisis'))
const esExcepcion = computed(() => props.estadoNombre === 'Observado' || props.estadoNombre === 'Rechazado')

const ordenActual = computed(() => {
  const estado = flow.value.find((e) => e.nombre === props.estadoNombre)
  return estado ? estado.orden : null
})

const ramas = computed(() => [
  { nombre: 'Observado', color: '#E8A33D' },
  { nombre: 'Rechazado', color: '#D64545' },
  { nombre: 'Aprobado', color: '#3F9142' },
])

function clasePaso(estado) {
  if (props.estadoNombre === estado.nombre) return 'stepper-step--current'
  if (ordenActual.value !== null && estado.orden <= ordenActual.value) return 'stepper-step--done'
  return ''
}

function claseRama(rama) {
  if (props.estadoNombre === rama.nombre) return 'fork-chip--active'
  if (rama.nombre === 'Aprobado' && ordenActual.value !== null && ordenActual.value >= 5)
    return 'fork-chip--passed'
  if (props.estadoNombre === 'En análisis') return 'fork-chip--pending'
  if (esExcepcion.value && rama.nombre !== props.estadoNombre) return 'fork-chip--muted'
  return ''
}

function conectorClase(indice) {
  if (esExcepcion.value && indice >= indiceDecision.value) return 'stepper-connector--fork-off'
  const estado = flow.value[indice]
  if (ordenActual.value !== null && estado.orden < ordenActual.value) return 'stepper-connector--done'
  return ''
}
</script>

<template>
  <div class="stepper" role="list" aria-label="Progreso del flujo">
    <template v-for="(estado, i) in flow" :key="estado.estado_id">
      <div
        class="stepper-step"
        :class="[clasePaso(estado), { 'stepper-step--decision': estado.nombre === 'En análisis' }]"
        role="listitem"
      >
        <div class="stepper-node">{{ i + 1 }}</div>
        <span class="stepper-label">{{ estado.nombre }}</span>
      </div>

      <div
        v-if="i === indiceDecision"
        class="stepper-fork"
        role="group"
        aria-label="Punto de decisión"
      >
        <span
          v-for="rama in ramas"
          :key="rama.nombre"
          class="fork-chip"
          :class="claseRama(rama)"
          :style="{ '--chip-color': rama.color }"
        >
          <span class="dot" aria-hidden="true"></span>
          {{ rama.nombre }}
        </span>
      </div>

      <div v-else-if="i < flow.length - 1" class="stepper-connector" :class="conectorClase(i)"></div>
    </template>
  </div>
</template>

<style scoped>
.stepper-connector--fork-off {
  background: #dde4eb;
  opacity: 0.5;
}

.stepper-connector--done {
  background: var(--ink-700);
}
</style>
