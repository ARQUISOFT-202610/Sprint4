"""
URL Configuration — AQSF Backend

Rutas de producción:
  POST /api/analisis/                          → Solicitar análisis (ASR-9)
  GET  /api/reportes/<id>/                     → Obtener reporte con verificación hash (ASR-11)
  GET  /api/reportes/<id>/verify/              → Verificar integridad SHA-256 (ASR-11)
  GET  /health/                                → Health check (sin autenticación)

Rutas de testing (solo DEBUG=True):
  POST /api/test/integrity-breach/<id>/        → Simular corrupción de hash (ASR-11)
  POST /api/test/write-rejection/              → Verificar rechazo de escritura AWS (ASR-11)
  GET  /api/test/anomaly-status/<empresa_id>/  → Estado del detector de anomalías (ASR-11)
"""
from django.http import JsonResponse
from django.urls import path

from interfaces.api.controllers import AnalisisController, ReporteController
from interfaces.api.integrity_controller import (
    IntegrityVerifyController,
    IntegrityBreachSimulatorController,
    WriteRejectionTestController,
    AnomalyStatusController,
)

urlpatterns = [
    # ----------------------------------------------------------------
    # Producción
    # ----------------------------------------------------------------
    # ASR-9: Análisis asíncrono — retorna 202 inmediatamente
    path("api/analisis/",
         AnalisisController.as_view(),
         name="analisis-create"),

    # ASR-11: Obtener reporte (incluye verificación de hash)
    path("api/reportes/<str:analisis_id>/",
         ReporteController.as_view(),
         name="reporte-detail"),

    # ASR-11: Verificación de integridad aislada (sin devolver contenido completo)
    path("api/reportes/<str:analisis_id>/verify/",
         IntegrityVerifyController.as_view(),
         name="reporte-verify"),

    # Health check (excluido en Auth0SecurityMiddleware)
    path("health/",
         lambda request: JsonResponse({"status": "ok", "service": "aqsf-backend"})),

    # ----------------------------------------------------------------
    # Testing (solo disponibles con DEBUG=True — retornan 404 en producción)
    # ----------------------------------------------------------------
    # ASR-11: Simular corrupción de hash para probar detección
    path("api/test/integrity-breach/<str:analisis_id>/",
         IntegrityBreachSimulatorController.as_view(),
         name="test-integrity-breach"),

    # ASR-11: Verificar que escritura sobre AWS es rechazada
    path("api/test/write-rejection/",
         WriteRejectionTestController.as_view(),
         name="test-write-rejection"),

    # ASR-11: Consultar contador de anomalías activas para una empresa
    path("api/test/anomaly-status/<str:empresa_id>/",
         AnomalyStatusController.as_view(),
         name="test-anomaly-status"),
]
