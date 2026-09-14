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

## Probar por consola

```bash
python -m app.extractor "C:\ruta\Solicitud de Compra 1307.pdf"
```
