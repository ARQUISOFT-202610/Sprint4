# Instrucciones de Ejecución — Pruebas JMeter AQSF

## Prerrequisitos

- JMeter 5.6+ instalado
- Servidor Django corriendo: `DJANGO_SETTINGS_MODULE=config.django_settings python manage.py runserver`
- Celery Worker activo: `celery -A infrastructure.messaging.celery_app worker --loglevel=info`
- Token Auth0 válido (obtener desde el flujo de login de la app o via Auth0 Machine-to-Machine)
- Una empresa registrada en la BD con el EMPRESA_ID configurado
- Para Experimento 3: `DEBUG=True` en el servidor Django (endpoints de testing)

---

## Experimento 1 — ASR-9 Disponibilidad

**Archivo:** `experimento1_asr9_disponibilidad.jmx`

### Configuración antes de ejecutar

Editar las variables globales en JMeter GUI o via CLI:

| Variable         | Valor                                       |
|-----------------|---------------------------------------------|
| `HOST`          | IP pública del EC2 Django (o `localhost`)   |
| `PORT`          | `8000` (o `80` si hay ALB)                  |
| `AUTH_TOKEN`    | Token JWT válido obtenido de Auth0          |
| `EMPRESA_ID`    | UUID de empresa existente en la BD          |

### Ejecución en modo GUI (recomendado para verificación inicial)

```bash
jmeter -t experimento1_asr9_disponibilidad.jmx
```

### Ejecución en modo headless (recomendado para prueba de carga real)

```bash
mkdir -p results
jmeter -n \
  -t experimento1_asr9_disponibilidad.jmx \
  -l results/asr9_run.jtl \
  -e -o results/asr9_report/ \
  -JHOST=<IP_EC2> \
  -JPORT=80 \
  -JAUTH_TOKEN=<TOKEN> \
  -JEMPRESA_ID=<UUID>
```

El reporte HTML estará en `results/asr9_report/index.html`.

### Criterios de PASO/FALLO para ASR-9

| Métrica                        | Umbral requerido | Dónde verificar           |
|-------------------------------|------------------|---------------------------|
| HTTP Status Code               | 202 en TG1       | Summary Report → Error %  |
| Tasa de éxito TG1              | **≥ 99%**        | Summary Report → Error %  |
| Tiempo respuesta P95           | < 2000 ms        | Aggregate Report → 95th % |
| HTTP Status sin token (TG2)    | 401 en 100%      | Summary Report TG2        |
| HTTP Status payload malo (TG3) | 400 en 100%      | Summary Report TG3        |

> **Verificación ASR-9 completada si:** Error % del TG1 ≤ **1.0%** y P95 < 2000ms.

### Verificación del correo (fuera de JMeter)

Después de ejecutar TG1, verificar en AWS SES Console o en el correo del solicitante:
1. Abrir SES → **Suppression List / Sending Statistics**
2. Confirmar que se enviaron correos con asunto "✅ Análisis completado — ..."
3. Verificar que los correos de error (si los hay) tienen asunto "❌ Error en análisis..."

---

## Experimento 2 — ASR-10 Seguridad / Confidencialidad

**Archivo:** `experimento2_asr10_seguridad_confidencialidad.jmx`

### Configuración antes de ejecutar

| Variable         | Valor                                                  |
|-----------------|--------------------------------------------------------|
| `TOKEN_EMPRESA_A` | Token JWT válido de un usuario de empresa A           |
| `EMPRESA_A_ID`  | UUID de empresa A (dueña del token)                    |
| `EMPRESA_B_ID`  | UUID de empresa B (víctima — no debe ser accesible)    |
| `TOKEN_FORJADO` | JWT con firma inválida (preconfigurado en el .jmx)     |
| `TOKEN_EXPIRADO`| JWT expirado generado previamente                      |

### Ejecución headless

```bash
mkdir -p results
jmeter -n \
  -t experimento2_asr10_seguridad_confidencialidad.jmx \
  -l results/asr10_run.jtl \
  -e -o results/asr10_report/ \
  -JHOST=<IP_EC2> -JPORT=80 \
  -JTOKEN_EMPRESA_A=<TOKEN_A> \
  -JEMPRESA_A_ID=<UUID_A> \
  -JEMPRESA_B_ID=<UUID_B>
```

### Criterios de PASO/FALLO para ASR-10

| Thread Group | Vector                       | Código esperado | Criterio PASO          |
|-------------|------------------------------|-----------------|------------------------|
| TG1 (200 req) | Sin token                  | 401             | Error % = **0%**       |
| TG2 (200 req) | JWT forjado                | 401             | Error % = **0%**       |
| TG3 (200 req) | JWT expirado (replay)      | 401             | Error % = **0%**       |
| TG4 (400 req) | Cross-tenant (A→datos B)   | 403             | Error % = **0%**       |
| TG5 (20 req)  | Brute force                | 401 → 429       | Rate limit activo      |

> **Verificación ASR-10 completada si:** Error % de todos los TGs = **0%** (0 accesos no autorizados exitosos).

---

## Experimento 3 — ASR-11 Seguridad / Integridad

**Archivo:** `experimento3_asr11_integridad.jmx`

### Prerrequisitos adicionales

1. Servidor Django con `DEBUG=True` (habilita endpoints `/api/test/*`)
2. Tener el UUID de un análisis en estado `COMPLETADO` (ejecutar primero ASR-9)
3. Redis activo para el detector de anomalías

### Configuración antes de ejecutar

| Variable                  | Valor                                              |
|--------------------------|----------------------------------------------------|
| `ANALISIS_ID_COMPLETADO` | UUID de análisis con estado COMPLETADO y hash SHA-256 |
| `EMPRESA_ID`             | UUID de empresa correspondiente al análisis        |
| `DETECTION_TIMEOUT_MS`   | `60000` (60 segundos — umbral ASR-11)              |

### Ejecución headless

```bash
mkdir -p results
jmeter -n \
  -t experimento3_asr11_integridad.jmx \
  -l results/asr11_run.jtl \
  -e -o results/asr11_report/ \
  -JHOST=<IP_EC2> -JPORT=8000 \
  -JAUTH_TOKEN=<TOKEN> \
  -JEMPRESA_ID=<UUID_EMPRESA> \
  -JANALISIS_ID_COMPLETADO=<UUID_ANALISIS>
```

### Alternativa: Script Python (más legible para presentación)

```bash
pip install requests
python tests/scripts/simulate_integrity_breach.py \
  --host <IP_EC2> --port 8000 \
  --token <TOKEN_AUTH0> \
  --empresa-id <UUID_EMPRESA> \
  --num-brechas 4 \
  --wait-complete
```

### Criterios de PASO/FALLO para ASR-11

| Thread Group | Qué verifica                         | Criterio PASO                       |
|-------------|---------------------------------------|-------------------------------------|
| SETUP       | Análisis creado (202)                 | HTTP 202 ✅                         |
| TG1         | Hash íntegro → 200 + integro=true    | Error % = **0%**                    |
| TG2         | Brecha detectada → 409 + < 60 000ms  | Detección **< 60s**, Error % = **0%** |
| TG3         | Escritura AWS rechazada               | rechazado=true en **100%**          |
| TG4         | 4 brechas → 409 en cada una           | Error % = **0%**                    |
| TG5         | Anomalía activa tras umbral           | anomalia_activa = **true**          |

---

## Orden de ejecución recomendado

```
1. ASR-9  → experimento1_asr9_disponibilidad.jmx         (obtener analisis_id completado)
2. ASR-10 → experimento2_asr10_seguridad_confidencialidad.jmx
3. ASR-11 → experimento3_asr11_integridad.jmx             (usar analisis_id de paso 1)
```

---

## Estructura de resultados esperada

```
results/
├── asr9_summary.csv       # Resumen ASR-9: tasa éxito ≥ 99%
├── asr9_aggregate.csv     # Percentiles ASR-9
├── asr10_summary.csv      # Resumen ASR-10: 0% penetración
├── asr11_summary.csv      # Resumen ASR-11: 100% detección < 60s
└── asr*_report/
    └── index.html         # Dashboard HTML interactivo por experimento
```

---

## Troubleshooting

| Síntoma                              | Causa probable                      | Solución                                      |
|-------------------------------------|-------------------------------------|-----------------------------------------------|
| TG1 retorna 401 en ASR-9            | Token expirado                      | Renovar AUTH_TOKEN                            |
| Error 500 en todos los endpoints     | Django no conecta a RDS o SQS       | Revisar `.env` y estado de servicios AWS      |
| Error % > 1% en ASR-9 TG1           | SQS throttling o Django lento       | Escalar EC2 o reducir hilos                   |
| TG2 retorna 202 en ASR-10           | Middleware no en MIDDLEWARE settings | Verificar orden en `django_settings.py`       |
| TG2 ASR-11 retorna 200 en vez de 409| Endpoint de breach retorna 404      | Verificar `DEBUG=True` en Django              |
| anomalia_activa = false en TG5      | Redis no disponible o contador bajo | Verificar Redis, aumentar `--num-brechas`     |
| TG2 ASR-11 falla por tiempo > 60s  | SES tardando en responder            | Verificar conectividad SES o usar mock SES    |
