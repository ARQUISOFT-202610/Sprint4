# Pasos Manuales Después del Despliegue de Terraform

Este documento detalla los pasos de configuración manual necesarios después de desplegar la infraestructura de ArquiSoft con Terraform.

## Tabla de Contenidos

1. [Verificación de Identidades en AWS SES](#verificación-de-identidades-en-aws-ses)
2. [Creación de Plantillas de Correo en AWS SES](#creación-de-plantillas-de-correo-en-aws-ses)
3. [Información del Certificado HTTPS](#información-del-certificado-https)
4. [Puntos de Acceso a la Aplicación](#puntos-de-acceso-a-la-aplicación)

---

## Verificación de Identidades en AWS SES

Las cuentas de AWS Academy tienen permisos restringidos en SES. Las identidades de correo electrónico no se pueden verificar automáticamente a través de Terraform. Debe verificarlas manualmente en la Consola de AWS.

### Paso A: Verificar Correo de Remitente

1. **Acceder a la Consola de AWS SES**
   - Ir a: https://console.aws.amazon.com/ses/home
   - Asegúrese de estar en la región: **us-east-1**

2. **Crear/Verificar Identidad de Remitente**
   - Hacer clic en: "Verified Identities" (menú izquierdo)
   - Hacer clic en: "Create Identity"
   - Seleccionar: "Email address"
   - Ingresar: `noreply@arquisoft.com`
   - Hacer clic en: "Create identity"

3. **Completar la Verificación de Correo**
   - Revisar la bandeja de entrada de su correo para el mensaje de verificación de AWS
   - Hacer clic en el **enlace de verificación** del correo
   - Volver a la consola de AWS SES
   - Actualizar la página
   - El estado debe mostrar: **Verified** (Verificado)

### Paso B: Verificar Correo de Destinatario

Repetir el mismo proceso para el correo del destinatario:

1. Hacer clic en: "Create Identity"
2. Seleccionar: "Email address"
3. Ingresar: `c.ochoao@uniandes.edu.co`
4. Hacer clic en: "Create identity"
5. Revisar el correo para el enlace de verificación
6. Hacer clic en el enlace de verificación
7. Volver a la consola de AWS SES
8. Actualizar para confirmar: **Verified** (Verificado)

### Estado de Verificación

Después de completar ambos pasos, la página de Identidades Verificadas de AWS SES debe mostrar:

```
Remitente:     noreply@arquisoft.com       [Verificado]
Destinatario:  c.ochoao@uniandes.edu.co    [Verificado]
```

---

## Creación de Plantillas de Correo en AWS SES

La creación de plantillas también está restringida en cuentas de AWS Academy. Las plantillas deben crearse manualmente.

### Creación de Plantillas

1. **Acceder a la Consola de AWS SES**
   - Ir a: https://console.aws.amazon.com/ses/home
   - Región: **us-east-1**

2. **Crear Plantilla de Éxito**
   - Navegar a: "Email Templates" (menú izquierdo)
   - Hacer clic en: "Create Template"
   - Completar el formulario:
     - **Nombre de Plantilla:** `analisis-resultado-exito`
     - **Asunto:** `ArquiSoft: Análisis Completado Exitosamente`
     - **HTML:** Copiar contenido del archivo `terraform/modules/ses/templates/success_email.html`
     - **Texto:** Copiar contenido del archivo `terraform/modules/ses/templates/success_email.txt`
   - Hacer clic en: "Create template"

3. **Crear Plantilla de Error**
   - Hacer clic en: "Create Template" nuevamente
   - Completar el formulario:
     - **Nombre de Plantilla:** `analisis-resultado-error`
     - **Asunto:** `ArquiSoft: Análisis Completado con Errores`
     - **HTML:** Copiar contenido del archivo `terraform/modules/ses/templates/failure_email.html`
     - **Texto:** Copiar contenido del archivo `terraform/modules/ses/templates/failure_email.txt`
   - Hacer clic en: "Create template"

### Ubicación de Archivos de Plantillas

```
terraform/modules/ses/templates/
├── success_email.html
├── success_email.txt
├── failure_email.html
└── failure_email.txt
```

---

## Información del Certificado HTTPS

La aplicación utiliza un **certificado TLS auto-firmado** para encriptación HTTPS durante el desarrollo.

### Detalles del Certificado

- **Generado por:** Recurso de Terraform `tls_self_signed_cert`
- **Validez:** 365 días desde el despliegue
- **Algoritmo:** RSA 2048-bit
- **Nombre Común:** `arquisoft.local`
- **Organización:** ArquiSoft
- **Ubicación:**
  - Certificado: `~/.tls/arquisoft.crt`
  - Clave Privada: `~/.tls/arquisoft.key`

### Advertencia en el Navegador

Al acceder a la aplicación a través de HTTPS, el navegador mostrará:

```
Su conexión no es privada
NET::ERR_CERT_AUTHORITY_INVALID
```

Esto es **NORMAL** para certificados auto-firmados en desarrollo. La aplicación sigue siendo segura - la advertencia solo indica que ninguna Autoridad Certificadora de confianza firmó el certificado.

### Cómo Proceder en el Navegador

**Chrome/Edge:**
1. Hacer clic en el botón "Advanced" (Avanzado)
2. Hacer clic en el enlace "Proceed to arquisoft..." (Continuar)

**Firefox:**
1. Hacer clic en "Advanced..." (Avanzado)
2. Hacer clic en "Accept the Risk and Continue" (Aceptar el riesgo y continuar)

**Safari:**
1. Hacer clic en "Show Details" (Mostrar detalles)
2. Hacer clic en "Visit this website" (Visitar este sitio web)

### Opcional: Importar Certificado Localmente (macOS)

Para eliminar las advertencias del navegador durante pruebas locales, puede importar el certificado:

```bash
# Importar certificado al llavero del sistema
sudo security add-trusted-cert -d -r trustRoot \
  -k /Library/Keychains/System.keychain \
  ~/.tls/arquisoft.crt
```

Luego reinicie el navegador. La advertencia debe desaparecer.

---

## Puntos de Acceso a la Aplicación

### Obtener Salidas de Infraestructura

Después del despliegue, recupere todos los puntos de acceso de la aplicación:

```bash
cd terraform
terraform output infrastructure_summary
```

Esto muestra:

```
Resumen de Infraestructura:
  Frontend (HTTPS):    https://arquisoft-alb-XXXXX.us-east-1.elb.amazonaws.com
  API Backend:         https://arquisoft-alb-XXXXX.us-east-1.elb.amazonaws.com/api/
  Flower (Celery):     http://<celery-instance-ip>:5555
```

### Frontend (React)

- **Protocolo:** HTTPS (certificado auto-firmado)
- **Puerto:** 443 (por defecto)
- **URL:** `https://<alb-dns>`
- **Redirección:** HTTP (puerto 80) redirige a HTTPS

Ejemplo:
```
https://arquisoft-alb-abcd1234.us-east-1.elb.amazonaws.com
```

### API Backend (Django)

- **Protocolo:** HTTP (proxied a través de Nginx)
- **Ruta:** `/api/`
- **URL:** `https://<alb-dns>/api/`

Ejemplo:
```
https://arquisoft-alb-abcd1234.us-east-1.elb.amazonaws.com/api/
```

El proxy de Nginx del frontend reenvía las solicitudes `/api/*` al backend de ALB de Django.

### FastAPI Microservice

FastAPI es un microservicio nuevo desplegado junto a Django, con su propio Auto Scaling Group.

- **Protocolo:** HTTP (proxied a través de ALB)
- **Puerto:** 8001 (puerto de aplicación), 80 (escuchador ALB)
- **URL:** `https://<alb-dns>/fastapi/`

**Para acceder a FastAPI:**

1. Obtener el punto de acceso de FastAPI a través del ALB (igual que Django):
   ```bash
   terraform output alb_dns_name
   ```

2. Acceder a través del ALB:
   ```
   https://<alb-dns>/fastapi/
   ```

3. Acceso directo a instancias (si es necesario):
   ```bash
   # Obtener IP de instancia de FastAPI
   aws autoscaling describe-auto-scaling-groups \
     --auto-scaling-group-names arquisoft-fastapi-asg \
     --region us-east-1 \
     --query 'AutoScalingGroups[0].Instances[0].[InstanceId,AvailabilityZone]' \
     --output table
   ```

### DynamoDB Local

DynamoDB Local se ejecuta en una instancia EC2 dedicada para persistencia de datos durante desarrollo/pruebas.

- **Protocolo:** HTTP (comunicación interna solo)
- **Puerto:** 8000
- **Punto de Acceso:** `http://<dynamodb-instance-ip>:8000`

**Detalles de DynamoDB Local:**

- Se ejecuta en **modo en-memoria** con base de datos compartida (`:sharedDb`)
- Utilizado exclusivamente por el microservicio FastAPI
- No es directamente accesible desde el frontend
- Los datos **no son persistentes** (se pierden al reiniciar)
- Adecuado solo para desarrollo y pruebas

**Para verificar que DynamoDB Local está ejecutándose:**

1. Obtener la IP de la instancia de DynamoDB:
   ```bash
   aws ec2 describe-instances \
     --filters "Name=tag:Name,Values=arquisoft-dynamodb-local" \
     --query 'Reservations[0].Instances[0].PublicIpAddress' \
     --region us-east-1
   ```

2. Verificar conectividad:
   ```bash
   curl http://<dynamodb-instance-ip>:8000/
   ```

3. O conectarse por SSH a la instancia:
   ```bash
   ssh -i ~/.ssh/arquisoft-key.pem ubuntu@<dynamodb-instance-ip>
   ```

---

## Lista de Verificación Post-Despliegue

Después del despliegue y configuración manual, verifique que todo funciona:

### Servicio de Correo

- [ ] Correo remitente `noreply@arquisoft.com` verificado en AWS SES (console.aws.amazon.com/ses)
- [ ] Correo destinatario `c.ochoao@uniandes.edu.co` verificado en AWS SES
- [ ] Plantilla de éxito `analisis-resultado-exito` creada en AWS SES
- [ ] Plantilla de error `analisis-resultado-error` creada en AWS SES

### HTTPS

- [ ] Frontend accesible en `https://<alb-dns>` (aceptar advertencia de certificado auto-firmado)
- [ ] HTTP redirige a HTTPS (acceder a `http://<alb-dns>`, debe redirigir)
- [ ] Archivos de certificado TLS presentes en `~/.tls/arquisoft.crt` y `~/.tls/arquisoft.key`

### Puntos de Acceso de la Aplicación

- [ ] Aplicación React del Frontend carga en `https://<alb-dns>`
- [ ] API es accesible en `https://<alb-dns>/api/`
- [ ] Verificación de salud: `/health` retorna "healthy"
- [ ] Flower de Celery accesible en `http://<celery-ip>:5555`

---

## Solución de Problemas

### Errores de Certificado

**Error:** `curl: (60) SSL certificate problem`

**Solución:** Usar la bandera `-k` o `--insecure` para omitir verificación de certificado:
```bash
curl -k https://arquisoft-alb-XXXXX.us-east-1.elb.amazonaws.com
```

### API Proxy No Funciona

**Error:** Registro de errores de Nginx: `name not known` o `connect() failed`

**Verificar:**
1. Que el ALB está ejecutándose:
   ```bash
   terraform output alb_dns_name
   ```

2. Que el DNS está correctamente inyectado en la configuración de Nginx:
   ```bash
   ssh -i ~/.ssh/arquisoft-key.pem ubuntu@<frontend-ip>
   grep proxy_pass /etc/nginx/sites-available/frontend
   ```

3. Conectividad del backend desde el frontend:
   ```bash
   curl http://<alb-dns>:8000/health
   ```

---

## Próximos Pasos

Después de completar la verificación:

1. Ejecutar pruebas de integración contra la aplicación
2. Configurar alarmas de CloudWatch para métricas críticas
3. Establecer monitoreo de costos y alertas
4. Planificar renovación de certificados (365 días antes de expiración)
5. Documentar cualquier configuración personalizada o cambios realizados

---

## Soporte y Preguntas

- Configuración de Terraform: `terraform/`
- Salidas de Infraestructura: `terraform output`
- Registros de CloudWatch: AWS Console > CloudWatch > Log Groups (console.aws.amazon.com/cloudwatch)
- Configuración de SES: AWS Console > SES > Verified Identities / Email Templates (console.aws.amazon.com/ses)

Para más información, consulte:
- Documentación de AWS SES: https://docs.aws.amazon.com/ses/
- Documentación de CloudWatch Logs: https://docs.aws.amazon.com/AmazonCloudWatch/latest/logs/
