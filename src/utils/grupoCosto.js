const PALETA_GRUPOS_COSTO = [
  { fondo: '#e8f3ff', borde: '#b8d8f5', texto: '#155b93', icono: '#2879b9' },
  { fondo: '#e8f7f0', borde: '#b8e3cf', texto: '#176846', icono: '#27855e' },
  { fondo: '#fff3df', borde: '#f3d3a0', texto: '#8a5200', icono: '#b76e00' },
  { fondo: '#f4edff', borde: '#d8c4f3', texto: '#60429a', icono: '#7954b4' },
  { fondo: '#ffecee', borde: '#f4c2c8', texto: '#9a3444', icono: '#bf4c60' },
  { fondo: '#e7f8f7', borde: '#afe0dc', texto: '#126a66', icono: '#258983' },
  { fondo: '#f8f0e5', borde: '#e5cfaa', texto: '#75521f', icono: '#987039' },
  { fondo: '#eef1f9', borde: '#cbd5ed', texto: '#465b91', icono: '#5f76ae' },
]

function indiceEstable(texto) {
  let hash = 0
  for (const caracter of texto) {
    hash = (hash * 31 + caracter.charCodeAt(0)) >>> 0
  }
  return hash % PALETA_GRUPOS_COSTO.length
}

/**
 * Devuelve los colores de una etiqueta de grupo de costo.
 * El resultado es determinista: el mismo grupo conserva siempre su color,
 * incluso cuando aparezcan grupos nuevos.
 */
export function estiloGrupoCosto(grupoCosto) {
  if (!grupoCosto) {
    return {
      '--grupo-costo-fondo': '#f4f8fa',
      '--grupo-costo-borde': '#d7e2ea',
      '--grupo-costo-texto': '#526576',
      '--grupo-costo-icono': '#7890a2',
    }
  }

  const color = PALETA_GRUPOS_COSTO[indiceEstable(grupoCosto.trim().toLocaleLowerCase())]
  return {
    '--grupo-costo-fondo': color.fondo,
    '--grupo-costo-borde': color.borde,
    '--grupo-costo-texto': color.texto,
    '--grupo-costo-icono': color.icono,
  }
}
