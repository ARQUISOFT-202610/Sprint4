#!/usr/bin/env python3
"""
Script de Simulación de Brecha de Integridad — ASR-11 AQSF

Uso:
  python simulate_integrity_breach.py --host localhost --port 8000 \
    --token <JWT_TOKEN> --empresa-id <UUID> --num-brechas 3

Descripción:
  1. Crea un análisis vía POST /api/analisis/
  2. Espera a que el Worker lo complete (polling sobre /api/reportes/<id>/verify/)
  3. Simula una brecha corrompiendo el hash vía POST /api/test/integrity-breach/<id>/
  4. Verifica que el sistema detecta la alteración con GET /api/reportes/<id>/verify/
  5. Mide el tiempo de detección y verifica que es < 60 segundos (ASR-11)
  6. Opcionalmente repite N veces para probar la detección de anomalías

Requisitos:
  pip install requests
  Django corriendo con DEBUG=True
"""

import argparse
import json
import sys
import time

import requests


def crear_analisis(base_url: str, token: str, empresa_id: str) -> str:
    """Crea un análisis y retorna su analisis_id."""
    resp = requests.post(
        f"{base_url}/api/analisis/",
        headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"},
        json={"empresa_id": empresa_id, "tipo_analisis": "optimizacion-costos"},
        timeout=10,
    )
    if resp.status_code != 202:
        print(f"❌ Error al crear análisis: {resp.status_code} — {resp.text}")
        sys.exit(1)
    analisis_id = resp.json()["analisis_id"]
    print(f"✅ Análisis creado: {analisis_id} (estado=PENDIENTE)")
    return analisis_id


def esperar_completado(base_url: str, token: str, analisis_id: str, timeout: int = 120) -> bool:
    """Polling hasta que el Worker complete el análisis o timeout."""
    headers = {"Authorization": f"Bearer {token}"}
    inicio = time.time()
    print(f"⏳ Esperando que el Worker complete el análisis {analisis_id}...")

    while time.time() - inicio < timeout:
        resp = requests.get(
            f"{base_url}/api/reportes/{analisis_id}/verify/",
            headers=headers, timeout=10,
        )
        data = resp.json()
        estado = data.get("estado") or data.get("mensaje", "")

        if "COMPLETADO" in str(estado) or data.get("integro") is not None:
            print(f"✅ Análisis completado. Estado actual del hash: íntegro={data.get('integro')}")
            return True

        time.sleep(5)
        print("   ... esperando (polling cada 5s)")

    print(f"⏱️ Timeout esperando completado del análisis {analisis_id}")
    return False


def simular_brecha(base_url: str, token: str, analisis_id: str, modo: str = "hash_invalido") -> bool:
    """Corrompe el hash del reporte via endpoint de testing."""
    resp = requests.post(
        f"{base_url}/api/test/integrity-breach/{analisis_id}/",
        headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"},
        json={"modo": modo},
        timeout=10,
    )
    if resp.status_code != 200:
        print(f"❌ Error al simular brecha: {resp.status_code} — {resp.text}")
        return False
    data = resp.json()
    print(f"🔥 Brecha simulada: hash {data['hash_original_preview']} → {data['hash_corrupto_preview']}")
    return True


def verificar_deteccion(base_url: str, token: str, analisis_id: str) -> dict:
    """
    Llama al endpoint de verificación y mide el tiempo de detección.
    Retorna los datos de la respuesta incluyendo tiempo_deteccion_ms.
    """
    headers = {"Authorization": f"Bearer {token}"}
    t_inicio = time.time()
    resp = requests.get(
        f"{base_url}/api/reportes/{analisis_id}/verify/",
        headers=headers, timeout=10,
    )
    t_total_ms = int((time.time() - t_inicio) * 1000)
    data = resp.json()
    data["tiempo_total_ms"] = t_total_ms
    data["http_status"] = resp.status_code
    return data


def verificar_anomalia(base_url: str, token: str, empresa_id: str) -> dict:
    """Consulta el estado del detector de anomalías."""
    resp = requests.get(
        f"{base_url}/api/test/anomaly-status/{empresa_id}/",
        headers={"Authorization": f"Bearer {token}"},
        timeout=10,
    )
    return resp.json()


def run(args):
    base_url = f"http://{args.host}:{args.port}"
    resultados = []

    print(f"\n{'='*60}")
    print(f"  Prueba ASR-11 Integridad — AQSF")
    print(f"  Host: {base_url}  |  Empresa: {args.empresa_id}")
    print(f"  Brechas a simular: {args.num_brechas}")
    print(f"{'='*60}\n")

    for i in range(1, args.num_brechas + 1):
        print(f"\n--- Brecha #{i} de {args.num_brechas} ---")

        # 1. Crear análisis
        analisis_id = crear_analisis(base_url, args.token, args.empresa_id)

        # 2. Esperar completado (opcional si el Worker es rápido)
        if args.wait_complete:
            ok = esperar_completado(base_url, args.token, analisis_id)
            if not ok:
                print("⚠️ Continuando sin esperar completado...")

        # 3. Simular brecha
        if not simular_brecha(base_url, args.token, analisis_id, modo=args.modo):
            continue

        # 4. Verificar detección — medir tiempo
        t0 = time.time()
        resultado = verificar_deteccion(base_url, args.token, analisis_id)
        t_deteccion_s = time.time() - t0

        # 5. Evaluar criterios ASR-11
        integro       = resultado.get("integro")
        http_status   = resultado.get("http_status")
        tiempo_ms     = resultado.get("tiempo_deteccion_ms", resultado.get("tiempo_total_ms", 0))
        cumple_60s    = tiempo_ms < 60_000

        print(f"\n  Resultado verificación:")
        print(f"    HTTP status          : {http_status}")
        print(f"    Integridad detectada : {'❌ COMPROMETIDA' if not integro else '✅ ÍNTEGRO'}")
        print(f"    Tiempo de detección  : {tiempo_ms}ms ({'✅ < 60s' if cumple_60s else '❌ > 60s'})")
        print(f"    ASR-11 alerta <60s   : {'✅ CUMPLIDO' if cumple_60s else '❌ INCUMPLIDO'}")

        if not integro and http_status == 409:
            print(f"    Hash almacenado      : {resultado.get('hash_almacenado', 'N/A')[:20]}...")
            print(f"    Hash actual          : {resultado.get('hash_actual', 'N/A')[:20]}...")

        resultados.append({
            "brecha_num":   i,
            "analisis_id":  analisis_id,
            "detectada":    (not integro) and http_status == 409,
            "tiempo_ms":    tiempo_ms,
            "cumple_60s":   cumple_60s,
        })

        # Pequeña pausa entre brechas
        if i < args.num_brechas:
            time.sleep(1)

    # 5. Verificar estado de detector de anomalías
    print(f"\n{'='*60}")
    print(f"  Estado del Detector de Anomalías (empresa {args.empresa_id[:8]}...)")
    print(f"{'='*60}")
    anomaly = verificar_anomalia(base_url, args.token, args.empresa_id)
    print(json.dumps(anomaly, indent=2))

    # 6. Resumen final
    print(f"\n{'='*60}")
    print(f"  Resumen Final — ASR-11")
    print(f"{'='*60}")
    total       = len(resultados)
    detectadas  = sum(1 for r in resultados if r["detectada"])
    cumplen_60s = sum(1 for r in resultados if r["cumple_60s"])

    print(f"  Brechas simuladas    : {total}")
    print(f"  Brechas detectadas   : {detectadas}/{total}  → {'✅ 100%' if detectadas == total else '❌ FALLO'}")
    print(f"  Alertas < 60s        : {cumplen_60s}/{total}  → {'✅ 100%' if cumplen_60s == total else '❌ FALLO'}")
    print(f"  Anomalía detectada   : {'✅ SÍ' if anomaly.get('anomalia_activa') else '⚠️ No (puede faltar umbral)'}")

    asr11_cumplido = (detectadas == total) and (cumplen_60s == total)
    print(f"\n  ASR-11 CUMPLIDO: {'✅ SÍ' if asr11_cumplido else '❌ NO'}")
    print(f"{'='*60}\n")

    sys.exit(0 if asr11_cumplido else 1)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Simulación de brecha de integridad — ASR-11 AQSF")
    parser.add_argument("--host",          default="localhost",     help="Host del servidor Django")
    parser.add_argument("--port",          default=8000, type=int,  help="Puerto")
    parser.add_argument("--token",         required=True,           help="JWT token Auth0 válido")
    parser.add_argument("--empresa-id",    required=True,           help="UUID de empresa de prueba")
    parser.add_argument("--num-brechas",   default=3, type=int,     help="Número de brechas a simular")
    parser.add_argument("--modo",          default="hash_invalido",
                        choices=["hash_invalido", "hash_parcial", "hash_aleatorio"],
                        help="Tipo de corrupción del hash")
    parser.add_argument("--wait-complete", action="store_true",
                        help="Esperar que el Worker complete antes de corromper")
    args = parser.parse_args()
    run(args)
