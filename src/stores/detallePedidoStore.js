import { defineStore } from 'pinia'
import { supabase } from '@/api/supabaseClient'
import { usePedidosStore } from '@/stores/pedidosStore'
import { useEstadosStore } from '@/stores/estadosStore'

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
        .order('fecha', { ascending: false })
        .order('historial_id', { ascending: false })
      this.loadingMapa[`hist-${detalleId}`] = false
      if (error) throw error
      this.historialPorItem[detalleId] = data
    },

    async fetchComentariosIncidencias(detalleIds) {
      if (!detalleIds?.length) return []

      const { data, error } = await supabase
        .from('detalle_historial_estados')
        .select('detalle_id, estado_id, comentario, fecha, historial_id')
        .in('detalle_id', detalleIds)
        .eq('active', true)
        .order('fecha', { ascending: false })
        .order('historial_id', { ascending: false })
      if (error) throw error
      return data
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

    async fetchIngresosItems(detalleIds) {
      if (!detalleIds?.length) return {}
      const { data, error } = await supabase
        .from('detalle_ingreso')
        .select('*')
        .in('detalle_id', detalleIds)
        .eq('active', true)
        .order('fecha', { ascending: false })
        .order('ingreso_id', { ascending: false })
      if (error) throw error
      const agrupados = {}
      for (const ingreso of data ?? []) {
        if (!agrupados[ingreso.detalle_id]) agrupados[ingreso.detalle_id] = []
        agrupados[ingreso.detalle_id].push(ingreso)
      }
      for (const detalleId of detalleIds) this.ingresosPorItem[detalleId] = agrupados[detalleId] ?? []
      return agrupados
    },

    async cambiarEstadoItem(detalleId, estadoId, comentario, fecha) {
      const { error } = await supabase
        .from('detalle_pedido')
        .update({ estado_actual_id: estadoId })
        .eq('detalle_id', detalleId)
      if (error) throw error
      await this._anotarMovimiento(detalleId, { fecha, comentario })
      await this._recargarTodo()
    },

    async aprobarItem(detalleId, estadoId, cantidadAprobada, comentario, fecha) {
      const { error } = await supabase
        .from('detalle_pedido')
        .update({ estado_actual_id: estadoId, cantidad_aprobada: cantidadAprobada })
        .eq('detalle_id', detalleId)
      if (error) throw error
      await this._anotarMovimiento(detalleId, { fecha, comentario })
      await this._recargarTodo()
    },

    async editarCantidadAprobada(detalleId, cantidad) {
      const { error } = await supabase
        .from('detalle_pedido')
        .update({ cantidad_aprobada: cantidad })
        .eq('detalle_id', detalleId)
      if (error) throw error

      const idAprobado = useEstadosStore().byName('Aprobado')?.estado_id
      if (idAprobado) {
        await supabase.from('detalle_historial_estados').insert({
          detalle_id: detalleId,
          estado_id: idAprobado,
          comentario: 'Aprobación ajustada',
        })
      }
      await this._recargarTodo()
    },

    async registrarIngreso(detalleId, cantidad, fecha, documento, comentario) {
      const { error } = await supabase
        .from('detalle_ingreso')
        .insert({
          detalle_id: detalleId,
          cantidad,
          fecha: fecha ?? null,
          documento: documento || null,
          comentario: comentario?.trim() || null,
        })
      if (error) throw error
      await this._recargarTodo()
    },

    async editarIngreso(ingresoId, { cantidad, fecha, documento }) {
      const { error } = await supabase
        .from('detalle_ingreso')
        .update({ cantidad, fecha, documento: documento || null })
        .eq('ingreso_id', ingresoId)
      if (error) throw error
      await this._recargarTodo()
    },

    async eliminarIngreso(ingresoId) {
      const { error } = await supabase
        .from('detalle_ingreso')
        .update({ active: false })
        .eq('ingreso_id', ingresoId)
      if (error) throw error
      await this._recargarTodo()
    },

    async eliminarItem(detalleId) {
      const { error } = await supabase
        .from('detalle_pedido')
        .update({ active: false })
        .eq('detalle_id', detalleId)
      if (error) throw error
      await this._recargarTodo()
    },

    async actualizarFechaAprox(detalleId, fecha) {
      const { error } = await supabase
        .from('detalle_pedido')
        .update({ fecha_aprox_atencion: fecha })
        .eq('detalle_id', detalleId)
      if (error) throw error
      await this._recargarTodo()
    },

    async cambiarEstadoItems({ pedidoId, estadoId, detalles, fecha, comentario }) {
      const { error } = await supabase.rpc('fn_cambiar_estado_items', {
        p_pedido_id: pedidoId,
        p_estado_id: estadoId,
        p_detalles: detalles,
        p_fecha: fecha ?? null,
        p_comentario: comentario?.trim() || null,
      })
      if (error) throw error
      await this._recargarTodo()
    },

    async editarComentarioMovimiento(historialId, comentario) {
      const { error } = await supabase.rpc('fn_editar_comentario_movimiento_detalle', {
        p_historial_id: historialId,
        p_comentario: comentario?.trim() || null,
      })
      if (error) throw error
    },

    async corregirUltimoMovimiento(detalleId, historialId, estadoId, motivo) {
      const { error } = await supabase.rpc('fn_corregir_ultimo_movimiento_detalle', {
        p_detalle_id: detalleId,
        p_historial_id: historialId,
        p_estado_id: estadoId,
        p_motivo: motivo.trim(),
      })
      if (error) throw error
      await this._recargarTodo()
    },

    async _anotarMovimiento(detalleId, { fecha, comentario }) {
      const { data: ultimo, error } = await supabase
        .from('detalle_historial_estados')
        .select('historial_id')
        .eq('detalle_id', detalleId)
        .order('historial_id', { ascending: false })
        .limit(1)
        .maybeSingle()
      if (error) throw error
      if (ultimo) {
        if (fecha) {
          const { error: fechaError } = await supabase
            .from('detalle_historial_estados')
            .update({ fecha })
            .eq('historial_id', ultimo.historial_id)
          if (fechaError) throw fechaError
        }
        if (comentario) await this.editarComentarioMovimiento(ultimo.historial_id, comentario)
      }
    },

    async _recargarTodo() {
      await this.cargar(this.pedidoId)
      try {
        await usePedidosStore().fetchPedidos()
      } catch (e) {
        /* el detalle ya se recargó; el listado se reintenta en la próxima transacción */
      }
    },
  },
})
