# AppSC PDF Extractor

Servicio local en Python para extraer solicitudes de compra desde PDF y devolver el JSON que AppSC usa para llenar el formulario.

## Instalacion normal

```bash
cd pdf-extractor
python -m venv .venv
.venv\Scripts\activate
pip install -r requirements.txt
```

## Ejecutar con Python instalado

```bash
uvicorn app.main:app --host 127.0.0.1 --port 8001
```

## Ejecutar en esta PC con dependencias locales

```powershell
.\run.ps1
```

AppSC intentara usar `http://127.0.0.1:8001/extract` cuando exista un archivo PDF seleccionado. Si el servicio no esta levantado, mantiene el flujo anterior con la Edge Function `leer-pdf`.

## Despliegue en Vercel

Este directorio puede desplegarse como un proyecto Vercel independiente desde el mismo repositorio:

- **Root Directory:** `pdf-extractor`
- **Variable de entorno:** `ALLOWED_ORIGINS=https://tu-app.vercel.app`

Luego configura en el proyecto Vercel del frontend la variable
`VITE_PDF_EXTRACTOR_URL` con la URL de este servicio. Por ejemplo:
`https://appsc-pdf-extractor.vercel.app`.

## Probar por consola

```bash
python -m app.extractor "C:\ruta\Solicitud de Compra 1307.pdf"
```
