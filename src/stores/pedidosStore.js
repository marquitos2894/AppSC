import { defineStore } from 'pinia'
import { supabase } from '@/api/supabaseClient'
import { SIN_GRUPO_COSTO, useFiltroGlobalStore } from '@/stores/filtroGlobalStore'
import { PENDIENTES_ATENCION } from '@/stores/estadosStore'

export const usePedidosStore = defineStore('pedidos', {
  state: () => ({
    pedidos: [],
    total: 0,
    loading: false,
    filtroEstado: null,
    busqueda: '',
  }),

  actions: {
    normalizarNroSc(nroSc) {
      const digitos = String(nroSc ?? '').replace(/\D/g, '')
      if (!digitos) return ''
      return digitos.replace(/^0+/, '') || '0'
    },

    async fetchPedidos() {
      this.loading = true
      const filtroGlobal = useFiltroGlobalStore()
      let query = supabase
        .from('vw_pedidos_resumen')
        .select('*', { count: 'exact' })
      if (this.filtroEstado === PENDIENTES_ATENCION) {
        query = query.in('estado_atencion', ['PENDIENTE', 'PARCIAL'])
      } else if (this.filtroEstado) {
        query = query.eq('estado_actual', this.filtroEstado)
      }
      if (filtroGlobal.grupoCosto === SIN_GRUPO_COSTO) {
        query = query.is('grupo_costo', null)
      } else if (filtroGlobal.grupoCosto) {
        query = query.eq('grupo_costo', filtroGlobal.grupoCosto)
      }
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

    async buscarPedidoPorNroSc(nroSc) {
      const normalizado = this.normalizarNroSc(nroSc)
      if (!normalizado) return null

      const { data, error } = await supabase
        .from('pedido')
        .select('pedido_id,nro_sc')
        .eq('active', true)
      if (error) throw error

      return data.find((pedido) => this.normalizarNroSc(pedido.nro_sc) === normalizado) ?? null
    },

    async crearPedido({ motivo, grupo_costo, nro_sc, fecha_emision, estadoId, items }) {
      const pedidoExistente = await this.buscarPedidoPorNroSc(nro_sc)
      if (pedidoExistente) {
        throw new Error(`El N° SC ${nro_sc} ya existe en el pedido #${pedidoExistente.pedido_id}`)
      }

      const { data: pedido, error: ePedido } = await supabase
        .from('pedido')
        .insert({ motivo, grupo_costo, nro_sc, fecha_emision, estado_actual_id: estadoId })
        .select()
        .single()
      if (ePedido) {
        if (ePedido.code === '23505') {
          throw new Error(`El N° SC ${nro_sc} ya existe en otro pedido`)
        }
        throw ePedido
      }

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
