import { defineStore } from 'pinia'
import { supabase } from '@/api/supabaseClient'

export const usePedidosStore = defineStore('pedidos', {
  state: () => ({
    pedidos: [],
    total: 0,
    loading: false,
    filtroEstado: null,
    busqueda: '',
  }),

  actions: {
    async fetchPedidos() {
      this.loading = true
      let query = supabase
        .from('vw_pedidos_resumen')
        .select('*', { count: 'exact' })
      if (this.filtroEstado) query = query.eq('estado_actual', this.filtroEstado)
      if (this.busqueda) {
        const term = this.busqueda.replace(/^sc/i, '')
        query = query.ilike('nro_sc', `%${term}%`)
      }
      const { data, error, count } = await query
        .order('fecha_emision', { ascending: false })
        .order('pedido_id', { ascending: false })
      this.loading = false
      if (error) throw error
      this.pedidos = data
      this.total = count
    },

    async crearPedido({ motivo, grupo_costo, nro_sc, fecha_emision, estadoId, items }) {
      const { data: pedido, error: ePedido } = await supabase
        .from('pedido')
        .insert({ motivo, grupo_costo, nro_sc, fecha_emision, estado_actual_id: estadoId })
        .select()
        .single()
      if (ePedido) throw ePedido

      const rows = items.map((item) => ({
        pedido_id: pedido.pedido_id,
        nro_parte: item.nro_parte || null,
        material: item.material || null,
        cantidad_solicitada: item.cantidad_solicitada,
        cantidad_aprobada: item.cantidad_aprobada ?? 0,
        equipo: item.equipo || null,
        estado_actual_id: item.estadoId ?? estadoId,
      }))

      if (rows.length) {
        const { error: eItems } = await supabase.from('detalle_pedido').insert(rows)
        if (eItems) throw eItems
      }
      return pedido
    },

    async eliminarPedido(pedidoId) {
      const { error } = await supabase
        .from('pedido')
        .update({ active: false })
        .eq('pedido_id', pedidoId)
      if (error) throw error
    },

    async autorizarPedido(pedidoId, fecha) {
      const { error } = await supabase
        .from('pedido')
        .update({ autorizado: fecha })
        .eq('pedido_id', pedidoId)
      if (error) throw error
    },
  },
})
