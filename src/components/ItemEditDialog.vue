<script setup>
import { ref, watch } from 'vue'
import { useItemsStore } from '@/stores/itemsStore'
import { useToast } from 'primevue/usetoast'
import { toLocalDate, toISODate } from '@/utils/format'

const props = defineProps({
  item: { type: Object, default: null },
  visible: { type: Boolean, default: false },
})
const emit = defineEmits(['update:visible', 'guardado'])

const itemsStore = useItemsStore()
const toast = useToast()
const saving = ref(false)
const formulario = ref({
  nro_parte: '',
  material: '',
  equipo: '',
  cantidad_solicitada: 0,
  cantidad_aprobada: 0,
  fecha_aprox_atencion: null,
})

watch(
  () => props.visible,
  (visible) => {
    if (visible && props.item) {
      formulario.value = {
        nro_parte: props.item.nro_parte || '',
        material: props.item.material || '',
        equipo: props.item.equipo || '',
        cantidad_solicitada: Number(props.item.cantidad_solicitada) || 0,
        cantidad_aprobada: Number(props.item.cantidad_aprobada) || 0,
        fecha_aprox_atencion: toLocalDate(props.item.fecha_aprox_atencion),
      }
    }
  },
)

async function guardar() {
  if (!props.item) return
  if (Number(formulario.value.cantidad_solicitada) < 0 || Number(formulario.value.cantidad_aprobada) < 0) return
  saving.value = true
  try {
    await itemsStore.editarItem(props.item.detalle_id, {
      nro_parte: formulario.value.nro_parte.trim() || null,
      material: formulario.value.material.trim() || null,
      equipo: formulario.value.equipo.trim() || null,
      cantidad_solicitada: Number(formulario.value.cantidad_solicitada) || 0,
      cantidad_aprobada: Number(formulario.value.cantidad_aprobada) || 0,
      fecha_aprox_atencion: toISODate(formulario.value.fecha_aprox_atencion),
    })
    toast.add({ severity: 'success', summary: 'Ítem actualizado', life: 3000 })
    emit('update:visible', false)
    emit('guardado')
  } catch (error) {
    toast.add({ severity: 'error', summary: 'No se pudo actualizar', detail: error.message, life: 6000 })
  } finally {
    saving.value = false
  }
}
</script>

<template>
  <Dialog
    :visible="visible"
    modal
    header="Editar ítem"
    :style="{ width: 'min(560px, calc(100vw - 2rem))' }"
    :closable="!saving"
    @update:visible="emit('update:visible', $event)"
  >
    <div v-if="item" class="item-edit-form">
      <div class="item-edit-identidad">
        <span class="mono">SC{{ item.nro_sc }}</span>
        <span>Modifica los datos del repuesto seleccionado.</span>
      </div>

      <div class="item-edit-grid">
        <div class="field-group">
          <label class="field-label" for="item-edit-nro-parte">Nro. parte</label>
          <InputText id="item-edit-nro-parte" v-model="formulario.nro_parte" fluid />
        </div>
        <div class="field-group">
          <label class="field-label" for="item-edit-equipo">Equipo</label>
          <InputText id="item-edit-equipo" v-model="formulario.equipo" fluid />
        </div>
        <div class="field-group item-edit-full">
          <label class="field-label" for="item-edit-material">Material</label>
          <InputText id="item-edit-material" v-model="formulario.material" fluid />
        </div>
        <div class="field-group">
          <label class="field-label" for="item-edit-solicitada">Cantidad solicitada</label>
          <InputNumber id="item-edit-solicitada" v-model="formulario.cantidad_solicitada" :min="0" :max-fraction-digits="2" fluid />
        </div>
        <div class="field-group">
          <label class="field-label" for="item-edit-aprobada">Cantidad aprobada</label>
          <InputNumber id="item-edit-aprobada" v-model="formulario.cantidad_aprobada" :min="0" :max-fraction-digits="2" fluid />
        </div>
        <div class="field-group item-edit-full">
          <label class="field-label" for="item-edit-fecha">Fecha aproximada de atención</label>
          <DatePicker id="item-edit-fecha" v-model="formulario.fecha_aprox_atencion" date-format="dd/mm/yy" show-icon fluid />
        </div>
      </div>

      <Message severity="info" :closable="false">
        El estado y la cantidad atendida se gestionan desde el flujo de atención.
      </Message>
    </div>

    <template #footer>
      <Button label="Cancelar" text severity="secondary" :disabled="saving" @click="emit('update:visible', false)" />
      <Button label="Guardar cambios" icon="pi pi-check" :loading="saving" @click="guardar" />
    </template>
  </Dialog>
</template>

<style scoped>
.item-edit-form { display: flex; flex-direction: column; gap: 18px; }
.item-edit-identidad { display: flex; flex-direction: column; gap: 3px; padding: 10px 12px; border-radius: 8px; background: #f4f8fa; color: var(--text-muted); font-size: 12px; }
.item-edit-identidad .mono { color: var(--text-strong); font-size: 13px; font-weight: 600; }
.item-edit-grid { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 14px; }
.item-edit-full { grid-column: 1 / -1; }
.field-group { display: flex; flex-direction: column; gap: 6px; }
.field-label { color: var(--text-muted); font-size: 11px; font-weight: 700; letter-spacing: .07em; text-transform: uppercase; }
@media (max-width: 520px) { .item-edit-grid { grid-template-columns: 1fr; } .item-edit-full { grid-column: auto; } }
</style>
