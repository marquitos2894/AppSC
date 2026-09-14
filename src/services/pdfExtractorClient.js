const DEFAULT_PDF_EXTRACTOR_URL = 'http://127.0.0.1:8001'

export async function extraerPdfLocal(file) {
  if (!file) return null

  const baseUrl = import.meta.env.VITE_PDF_EXTRACTOR_URL || DEFAULT_PDF_EXTRACTOR_URL
  const formData = new FormData()
  formData.append('file', file)

  const response = await fetch(`${baseUrl.replace(/\/$/, '')}/extract`, {
    method: 'POST',
    body: formData,
  })

  if (!response.ok) {
    let detail = `Extractor local respondió ${response.status}`
    try {
      const body = await response.json()
      detail = body?.detail || body?.error || detail
    } catch {
      /* respuesta no JSON */
    }
    throw new Error(detail)
  }

  return response.json()
}
