#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# verificar.sh — Sesión 1 del Laboratorio N.º 14
# Comprueba la segmentación (front/back), el aislamiento de la DB y el DNS
# interno. Úsalo con el stack SEGMENTADO ya levantado:
#
#   docker compose -f docker-compose.segmentado.yml up -d
#   ./verificar.sh
#
# Códigos de salida: 0 = todo OK, 1 = algún fallo.
# ---------------------------------------------------------------------------
set -uo pipefail
cd "$(dirname "$0")"

COMPOSE="docker compose -f docker-compose.segmentado.yml"
DNS_IP="172.28.10.53"          # contenedor dnsmasq (dns-corp)
DB_IP="172.28.20.20"           # db-srv (red back)
pass=0; fail=0

ok() { printf '  \033[32m[OK]\033[0m    %s\n' "$1"; pass=$((pass+1)); }
ko() { printf '  \033[31m[FALLO]\033[0m %s\n' "$1"; fail=$((fail+1)); }

echo "==============================================================="
echo " Verificación de la Sesión 1 — segmentación, aislamiento y DNS"
echo "==============================================================="

echo
echo "1) Estado del stack"
$COMPOSE ps

echo
echo "2) web NO debe resolver ni alcanzar la DB por nombre"
if $COMPOSE exec -T web getent hosts db >/dev/null 2>&1; then
  ko "web resolvió 'db' (no debería: db vive solo en la red back)"
else
  ok "web no resuelve 'db' (db está únicamente en 'back')"
fi

echo
echo "3) web NO debe alcanzar la DB por IP (prueba de ruteo, no de DNS)"
if $COMPOSE exec -T web sh -c "nc -z -w 3 $DB_IP 5432" >/dev/null 2>&1; then
  ko "web conectó a $DB_IP:5432 (revisa 'internal: true' y que db no publique puertos)"
else
  ok "web no alcanza $DB_IP:5432 (aislamiento de capa 3 confirmado)"
fi

echo
echo "4) api SÍ debe alcanzar la DB (es el puente front<->back)"
if $COMPOSE exec -T api python -c \
    "import socket as s; s.create_connection(('$DB_IP',5432),3)" >/dev/null 2>&1; then
  ok "api alcanza la DB en $DB_IP:5432"
else
  ko "api NO alcanza la DB en $DB_IP:5432"
fi

echo
echo "5) El DNS interno debe resolver web.local, api.local y db.local"
for pair in "web.local:172.28.10.10" "api.local:172.28.10.20" "db.local:172.28.20.20"; do
  name="${pair%%:*}"; ip="${pair##*:}"
  got="$($COMPOSE exec -T web nslookup "$name" "$DNS_IP" 2>/dev/null \
          | awk '/^Address: /{print $2}' | tail -1)"
  if [ "$got" = "$ip" ]; then
    ok "$name -> $ip"
  else
    ko "$name -> '$got' (esperado $ip)"
  fi
done

echo
echo "6) La web debe responder por el puerto publicado (8080)"
code="$(curl -s -o /dev/null -w '%{http_code}' http://localhost:8080 || true)"
if [ "$code" = "200" ]; then
  ok "http://localhost:8080 -> HTTP $code"
else
  ko "http://localhost:8080 -> HTTP '$code' (¿está web arriba?)"
fi

echo
echo "---------------------------------------------------------------"
printf ' Resultado: %d OK, %d FALLO\n' "$pass" "$fail"
echo "---------------------------------------------------------------"
[ "$fail" -eq 0 ]
