import { defineStore } from 'pinia'
import { supabase } from '@/api/supabaseClient'

export const useDetallePedidoStore = defineStore('detallePedido', {
  state: () => ({
    visible: false,
    pedidoId: null,
    pedido: null,
    items: [],
    historialPedido: [],
    historialPorItem: {},
    ingresosPorItem: {},
    loading: false,
    loadingMapa: {},
  }),

  getters: {
    estadoPedido: (s) => s.pedido?.estados_catalogo?.nombre,
    estadoAtencionPedido: (s) => s.pedido?.estado_atencion,
    pendiente: () => (item) =>
      Math.max(Number(item.cantidad_aprobada ?? 0) - Number(item.cantidad_atendida ?? 0), 0),
  },

  actions: {
    abrir(pedidoId) {
      this.visible = true
      this.pedidoId = pedidoId
      this.cargar(pedidoId)
    },

    cerrar() {
      this.visible = false
      this.pedidoId = null
      this.pedido = null
      this.items = []
      this.historialPedido = []
      this.historialPorItem = {}
      this.ingresosPorItem = {}
    },

    async cargar(pedidoId) {
      this.loading = true
      try {
        const [p, it, h] = await Promise.all([
          supabase
            .from('pedido')
            .select('*, estados_catalogo:estado_actual_id(nombre)')
            .eq('pedido_id', pedidoId)
            .single(),
          supabase
            .from('detalle_pedido')
            .select('*, estados_catalogo:estado_actual_id(nombre)')
            .eq('pedido_id', pedidoId)
            .eq('active', true)
            .order('detalle_id', { ascending: true }),
          supabase
            .from('solicitud_historial_estados')
            .select('*, estados_catalogo:estado_id(nombre)')
            .eq('pedido_id', pedidoId)
            .eq('active', true)
            .order('fecha', { ascending: false })
            .order('historial_id', { ascending: false }),
        ])
        if (p.error) throw p.error
        if (it.error) throw it.error
        if (h.error) throw h.error
        this.pedido = p.data
        this.items = it.data
        this.historialPedido = h.data
      } finally {
        this.loading = false
      }
    },

    async cargarHistorial(pedidoId) {
      this.loadingMapa.histPedido = true
      const { data, error } = await supabase
        .from('solicitud_historial_estados')
        .select('*, estados_catalogo:estado_id(nombre)')
        .eq('pedido_id', pedidoId)
        .eq('active', true)
        .order('fecha', { ascending: false })
        .order('historial_id', { ascending: false })
      this.loadingMapa.histPedido = false
      if (error) throw error
      this.historialPedido = data
    },

    async fetchHistorialItem(detalleId) {
      this.loadingMapa[`hist-${detalleId}`] = true
      const { data, error } = await supabase
        .from('detalle_historial_estados')
        .select('*, estados_catalogo:estado_id(nombre)')
        .eq('detalle_id', detalleId)
        .eq('active', true)
        .order('fecha', { ascending: true })
        .order('historial_id', { ascending: true })
      this.loadingMapa[`hist-${detalleId}`] = false
      if (error) throw error
      this.historialPorItem[detalleId] = data
    },

    async fetchIngresos(detalleId) {
      this.loadingMapa[`ing-${detalleId}`] = true
      const { data, error } = await supabase
        .from('detalle_ingreso')
        .select('*')
        .eq('detalle_id', detalleId)
        .eq('active', true)
        .order('fecha', { ascending: false })
      this.loadingMapa[`ing-${detalleId}`] = false
      if (error) throw error
      this.ingresosPorItem[detalleId] = data
    },

    async cambiarEstadoItem(detalleId, estadoId, comentario) {
      const { error } = await supabase
        .from('detalle_pedido')
        .update({ estado_actual_id: estadoId })
        .eq('detalle_id', detalleId)
      if (error) throw error
      if (comentario) await this._anotarComentario(detalleId, comentario)
      await this.cargar(this.pedidoId)
    },

    async aprobarItem(detalleId, estadoId, cantidadAprobada, comentario) {
      const { error } = await supabase
        .from('detalle_pedido')
        .update({ estado_actual_id: estadoId, cantidad_aprobada: cantidadAprobada })
        .eq('detalle_id', detalleId)
      if (error) throw error
      if (comentario) await this._anotarComentario(detalleId, comentario)
      await this.cargar(this.pedidoId)
    },

    async registrarIngreso(detalleId, cantidad) {
      const { error } = await supabase
        .from('detalle_ingreso')
        .insert({ detalle_id: detalleId, cantidad })
      if (error) throw error
      await this.cargar(this.pedidoId)
    },

    async eliminarItem(detalleId) {
      const { error } = await supabase
        .from('detalle_pedido')
        .update({ active: false })
        .eq('detalle_id', detalleId)
      if (error) throw error
      await this.cargar(this.pedidoId)
    },

    async _anotarComentario(detalleId, comentario) {
      const { data: ultimo } = await supabase
        .from('detalle_historial_estados')
        .select('historial_id')
        .eq('detalle_id', detalleId)
        .order('fecha', { ascending: false })
        .order('historial_id', { ascending: false })
        .limit(1)
        .maybeSingle()
      if (ultimo) {
        await supabase
          .from('detalle_historial_estados')
          .update({ comentario })
          .eq('historial_id', ultimo.historial_id)
      }
    },
  },
})
