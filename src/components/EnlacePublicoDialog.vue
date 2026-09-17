<script setup>
import { ref, watch } from 'vue'
import { supabase } from '@/api/supabaseClient'
import { useToast } from 'primevue/usetoast'

const props = defineProps({ visible: Boolean })
const emit = defineEmits(['update:visible'])
const toast = useToast()

const enlace = ref('')
const saving = ref(false)

watch(() => props.visible, (visible) => {
  if (!visible) enlace.value = ''
})

async function generar() {
  saving.value = true
  try {
    const { data, error } = await supabase.rpc('fn_generar_enlace_publico')
    if (error) throw error
    enlace.value = new URL(`/publico/${data}`, window.location.origin).toString()
    toast.add({ severity: 'success', summary: 'Enlace público creado', life: 3000 })
  } catch (error) {
    toast.add({ severity: 'error', summary: 'No se pudo generar el enlace', detail: error.message, life: 6000 })
  } finally {
    saving.value = false
  }
}

async function copiar() {
  try {
    await navigator.clipboard.writeText(enlace.value)
    toast.add({ severity: 'success', summary: 'Enlace copiado', life: 3000 })
  } catch {
    toast.add({ severity: 'warn', summary: 'Copia el enlace manualmente', life: 4000 })
  }
}

async function revocar() {
  saving.value = true
  try {
    const { error } = await supabase.rpc('fn_revocar_enlace_publico')
    if (error) throw error
    enlace.value = ''
    toast.add({ severity: 'success', summary: 'Acceso público revocado', life: 3000 })
  } catch (error) {
    toast.add({ severity: 'error', summary: 'No se pudo revocar', detail: error.message, life: 6000 })
  } finally {
    saving.value = false
  }
}
</script>

<template>
  <Dialog :visible="visible" modal header="Enlace público de solo lectura" :style="{ width: 'min(620px, 94vw)' }" @update:visible="emit('update:visible', $event)">
    <div class="flex flex-column gap-3">
      <Message severity="warn" :closable="false">
        El enlace permite consultar todos los pedidos y sus ítems sin iniciar sesión. No permite crear, editar ni eliminar información.
      </Message>
      <p class="m-0 text-sm" style="color: var(--text-muted)">
        Al generar un nuevo enlace, el anterior dejará de funcionar.
      </p>
      <InputText v-if="enlace" :model-value="enlace" readonly aria-label="Enlace público" />
    </div>

    <template #footer>
      <Button label="Revocar acceso" icon="pi pi-ban" text severity="danger" :loading="saving" @click="revocar" />
      <Button v-if="enlace" label="Copiar enlace" icon="pi pi-copy" :disabled="saving" @click="copiar" />
      <Button :label="enlace ? 'Generar otro enlace' : 'Generar enlace'" icon="pi pi-link" :loading="saving" @click="generar" />
    </template>
  </Dialog>
</template>
