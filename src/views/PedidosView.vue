<template>
  <div v-if="!configurado" class="setup-warning">
    <Message severity="warn" :closable="false">
      <div class="flex flex-column gap-1">
        <strong>Supabase no está configurado.</strong>
        <span>
          Crea un archivo <span class="mono">.env</span> en la raíz con
          <span class="mono">VITE_SUPABASE_URL</span> y
          <span class="mono">VITE_SUPABASE_ANON_KEY</span>, ejecuta
          <span class="mono">supabase/schema.sql</span> en el SQL Editor y reinicia
          <span class="mono">npm run dev</span>.
        </span>
      </div>
    </Message>
  </div>

  <div class="page-header">
    <h1 class="page-title">
      Pedidos
      <span v-if="total !== null && !pedidosStore.loading" class="mono-count mono">
        {{ total }}
      </span>
    </h1>

    <span class="p-input-icon-left page-search">
      <i class="pi pi-search"></i>
      <InputText
        v-model="busqueda"
        placeholder="Buscar por N° SC"
        fluid
        @keydown.enter="buscar"
        @keydown.esc="limpiarBusqueda"
      />
    </span>

    <Select
      v-model="filtroEstado"
      :options="estados"
      option-label="nombre"
      option-value="nombre"
      placeholder="Todos los estados"
      show-clear
      :loading="cargandoEstados"
      style="min-width: 200px"
    />

    <Button label="Nuevo pedido" icon="pi pi-plus" @click="abrirNuevo" />
  </div>

  <div class="page-content">
    <PedidosDataView
      @nuevo="abrirNuevo"
      @eliminar="confirmarEliminar"
      @cambiar-estado="abrirCambiarEstado"
      @historial="abrirHistorial"
      @autorizar="abrirAutorizar"
      @generar-resumen="abrirResumen"
    />
  </div>

  <PedidoDetailPanel />
  <PedidoResumenDialog
    v-model:visible="dialogResumen"
    :pedido="resumenPedido"
    :items="resumenItems"
    :estado-pedido="resumenEstado"
  />
  <PedidoFormDialog v-model:visible="dialogNuevo" @creado="alCrear" />
  <CambiarEstadoPedidoDialog
    v-model:visible="dialogCambiarEstado"
    :pedido="pedidoSeleccionado"
    @cambiado="alCambiarEstado"
  />
  <HistorialPedidoDialog
    v-model:visible="dialogHistorial"
    :pedido="pedidoSeleccionado"
  />
  <AutorizarPedidoDialog
    v-model:visible="dialogAutorizar"
    :pedido="pedidoSeleccionado"
    @autorizado="alAutorizar"
  />
</template>


<script setup>
import { ref, onMounted, watch } from 'vue'
import { storeToRefs } from 'pinia'
import { isConfigured } from '@/api/supabaseClient'
import { useEstadosStore } from '@/stores/estadosStore'
import { usePedidosStore } from '@/stores/pedidosStore'
import { useDetallePedidoStore } from '@/stores/detallePedidoStore'
import { useFiltroGlobalStore } from '@/stores/filtroGlobalStore'
import { useConfirm } from 'primevue/useconfirm'
import { useToast } from 'primevue/usetoast'
import PedidosDataView from '@/components/PedidosDataView.vue'
import PedidoDetailPanel from '@/components/PedidoDetailPanel.vue'
import PedidoFormDialog from '@/components/PedidoFormDialog.vue'
import CambiarEstadoPedidoDialog from '@/components/CambiarEstadoPedidoDialog.vue'
import HistorialPedidoDialog from '@/components/HistorialPedidoDialog.vue'
import AutorizarPedidoDialog from '@/components/AutorizarPedidoDialog.vue'
import PedidoResumenDialog from '@/components/PedidoResumenDialog.vue'

const estadosStore = useEstadosStore()
const pedidosStore = usePedidosStore()
const detalleStore = useDetallePedidoStore()
const filtroGlobalStore = useFiltroGlobalStore()
const confirm = useConfirm()
const toast = useToast()

const { estados, loading: cargandoEstados } = storeToRefs(estadosStore)
const { total } = storeToRefs(pedidosStore)
const { pedido: resumenPedido, items: resumenItems, estadoPedido: resumenEstado } = storeToRefs(detalleStore)

const dialogNuevo = ref(false)
const dialogCambiarEstado = ref(false)
const dialogHistorial = ref(false)
const dialogAutorizar = ref(false)
const dialogResumen = ref(false)
const pedidoSeleccionado = ref(null)
const configurado = isConfigured

const filtroEstado = ref({
  get: () => pedidosStore.filtroEstado,
  set: (v) => {
    pedidosStore.filtroEstado = v
    cargar().catch((e) => notificarError(e))
  },
})

const busqueda = ref('')

onMounted(async () => {
  if (!configurado) return
  try {
    await estadosStore.load()
    await pedidosStore.fetchPedidos()
  } catch (e) {
    notificarError(e)
  }
})

watch(
  () => filtroGlobalStore.grupoCosto,
  () => cargar().catch((e) => notificarError(e)),
)

async function cargar() {
  await pedidosStore.fetchPedidos()
}

function notificarError(e) {
  toast.add({
    severity: 'error',
    summary: 'Error de conexión',
    detail: e?.message || 'No se pudo conectar con Supabase.',
    life: 6000,
  })
}

function buscar() {
  pedidosStore.busqueda = busqueda.value
  cargar().catch((e) => notificarError(e))
}

function limpiarBusqueda() {
  busqueda.value = ''
  pedidosStore.busqueda = ''
  cargar().catch((e) => notificarError(e))
}

function abrirNuevo() {
  dialogNuevo.value = true
}

function abrirCambiarEstado(pedido) {
  pedidoSeleccionado.value = pedido
  dialogCambiarEstado.value = true
}

function abrirHistorial(pedido) {
  pedidoSeleccionado.value = pedido
  dialogHistorial.value = true
}

function abrirAutorizar(pedido) {
  pedidoSeleccionado.value = pedido
  dialogAutorizar.value = true
}

async function abrirResumen(pedido) {
  try {
    await detalleStore.cargar(pedido.pedido_id)
    dialogResumen.value = true
  } catch (e) {
    notificarError(e)
  }
}

async function alAutorizar() {
  try {
    await cargar()
    if (pedidoSeleccionado.value && detalleStore.pedidoId === pedidoSeleccionado.value.pedido_id) {
      await detalleStore.cargar(detalleStore.pedidoId)
    }
  } catch (e) {
    notificarError(e)
  }
}

async function alCambiarEstado() {
  try {
    await cargar()
    if (pedidoSeleccionado.value && detalleStore.pedidoId === pedidoSeleccionado.value.pedido_id) {
      await detalleStore.cargar(detalleStore.pedidoId)
    }
    if (dialogHistorial.value && pedidoSeleccionado.value) {
      await detalleStore.cargarHistorial(pedidoSeleccionado.value.pedido_id)
    }
  } catch (e) {
    notificarError(e)
  }
}

function alCrear(pedidoId) {
  cargar().catch((e) => notificarError(e))
  detalleStore.abrir(pedidoId)
}

function confirmarEliminar(row) {
  confirm.require({
    message: `¿Eliminar el pedido #${row.pedido_id}? Se aplicará borrado lógico y dejará de aparecer en el listado.`,
    header: 'Eliminar pedido',
    icon: 'pi pi-trash',
    rejectLabel: 'Cancelar',
    acceptLabel: 'Eliminar',
    acceptProps: { severity: 'danger' },
    accept: async () => {
      try {
        await pedidosStore.eliminarPedido(row.pedido_id)
        await cargar()
        toast.add({ severity: 'success', summary: 'Pedido eliminado', life: 3000 })
      } catch (e) {
        notificarError(e)
      }
    },
  })
}
</script>
