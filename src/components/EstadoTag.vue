<script setup>
import { computed } from 'vue'
import { estadoColor } from '@/stores/estadosStore'

const props = defineProps({
  nombre: { type: String, required: true },
  size: { type: String, default: 'md' },
})

const color = computed(() => estadoColor(props.nombre))

const style = computed(() => ({
  color: color.value,
  background: `${color.value}1A`,
  borderColor: `${color.value}40`,
}))
</script>

<template>
  <span
    class="estado-tag"
    :class="{ 'estado-tag--sm': size === 'sm' }"
    :style="style"
  >
    <span class="dot" aria-hidden="true"></span>
    {{ nombre }}
  </span>
</template>
