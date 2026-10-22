# Sesión 1 — Archivos Docker + paso a paso detallado

Material de la **Sesión 1** del Laboratorio N.º 14. Aquí está todo lo necesario
para levantar el stack, **ver el problema de la red plana** y refactorizarlo a
**subredes** (`front`/`back`) con **DNS interno**.

> **Sesión independiente:** no necesitas las otras sesiones ni Packet Tracer.

Guía académica con teoría, checkpoints y preguntas evaluadas:
[SESION-1.md](../SESION-1.md) · Teoría de apoyo: [TEORIA.md](../TEORIA.md)

---

## 0. Qué hay en esta carpeta

| Archivo | Para qué |
|---------|----------|
| `docker-compose.yml` | **Paso 1:** el primer stack en **red plana** (web/api/db). |
| `docker-compose.segmentado.yml` | **Paso 3:** el mismo stack con `front`/`back`, `internal: true` y DNS. |
| `dnsmasq.conf` | Zonas DNS internas (`web.local`, `api.local`, `db.local`). |
| `api/` | Código (`app.py`) y `Dockerfile` de la API (Flask). Expone `/ping` y `/db`. |
| `api.zip` | El mismo `api/` comprimido, para descargarlo suelto. |
| `verificar.sh` | **Verificación automática**: 7 pruebas de segmentación, aislamiento y DNS. |

---

## 1. Cómo obtener estos archivos

Si ya los tienes, ve al [paso 2](#2-antes-de-empezar). Si no, elige un método:

### Método A — `git clone` (recomendado)

```bash
git clone https://github.com/isacioutp/lab-8-docker-compose.git
cd lab-8-docker-compose/sesion-1
```

Ventaja para esta sesión: conservas el historial, así que puedes **ver qué
cambiaste** (`git diff`) y **deshacerlo** (`git checkout -- .`) entre
experimentos. Es lo que hace cómodo el
[Laboratorio de experimentos](#7--laboratorio-de-experimentos).

> Por SSH: `git clone git@github.com:isacioutp/lab-8-docker-compose.git`

### Método B — ZIP del repositorio

Página del repo → **Code** → **Download ZIP** → descomprime → entra en
`lab-8-docker-compose-main/sesion-1/`.

### Método C — Archivos sueltos

```bash
BASE=https://raw.githubusercontent.com/isacioutp/lab-8-docker-compose/main/sesion-1
curl -O $BASE/docker-compose.segmentado.yml
curl -O $BASE/docker-compose.yml
curl -O $BASE/dnsmasq.conf
curl -O $BASE/verificar.sh
curl -O $BASE/api/app.py
curl -O $BASE/api/Dockerfile
```

### Método D — Copiar la carpeta

```bash
cp -r /ruta/al/material/sesion-1 ~/lab14/sesion-1
cd ~/lab14/sesion-1
```

> **Regla:** trabaja siempre **dentro** de `sesion-1/`. Compose deriva el nombre
> del proyecto del nombre de la carpeta, y los comandos de esta guía asumen que
> estás ahí.

---

## 2. Antes de empezar

```bash
# 1) Docker Engine + plugin compose
docker --version
docker compose version

# 2) el puerto 8080 libre (lo usará la web)
(ss -ltn 2>/dev/null || netstat -ltn) | grep ':8080' && echo "OCUPADO" || echo "8080 libre"

# 3) empezar limpio: todas las sesiones usan las mismas subredes
docker compose -f docker-compose.segmentado.yml down -v --remove-orphans 2>/dev/null || true
```

> ⚠️ **Las 4 sesiones del lab usan las mismas subredes** (`172.28.10.0/24` y
> `172.28.20.0/24`). Baja un stack (`down -v`) antes de levantar otro, o
> Docker se quejará de que la subred ya existe.

---

## 3. Paso 1 — Tu primer stack (red plana)

### 3.1 Qué significa cada línea

```yaml
services:
  web:
    image: nginx:alpine
    ports: ["8080:80"]        # publica el puerto 80 del contenedor en el 8080 del host

  api:
    build: ./api              # construye la imagen desde ./api/Dockerfile

  db:
    image: postgres:15-alpine
    environment:
      POSTGRES_PASSWORD: labpass123
```

Y **lo que no dice**: ninguna red, ni IP, ni DNS. Compose las crea igualmente.

### 3.2 Levantar y mirar

```bash
docker compose up -d
docker compose ps
curl -s -o /dev/null -w "web responde %{http_code}\n" http://localhost:8080
```

```text
NAME              IMAGE               ...   PORTS
sesion-1-api-1    sesion-1-api        ...   8000/tcp
sesion-1-db-1     postgres:15-alpine  ...   5432/tcp
sesion-1-web-1    nginx:alpine        ...   0.0.0.0:8080->80/tcp
web responde 200
```

Un solo YAML levantó tres servicios. **No escribiste ni un `docker run`.** Eso
es orquestación en su forma más simple: tú declaras *qué* quieres y Compose
resuelve *cómo*.

### 3.3 La red que Compose creó solo

```bash
docker network ls | grep sesion-1
docker network inspect sesion-1_default \
  --format '{{range .IPAM.Config}}subred={{.Subnet}} gateway={{.Gateway}}{{end}}'
docker inspect sesion-1-web-1 \
  --format '{{range $k,$v := .NetworkSettings.Networks}}{{$k}}={{$v.IPAddress}}{{end}}'
docker compose exec web cat /etc/resolv.conf
```

```text
subred=172.18.0.0/16 gateway=172.18.0.1
sesion-1_default=172.18.0.3
nameserver 127.0.0.11
```

Fíjate en lo importante: **los tres servicios comparten la misma red**. Eso es
una **red plana**.

---

## 4. Paso 2 — El problema: en la red plana todos se ven

```bash
# la web resuelve el nombre de la BD...
docker compose exec web getent hosts db

# ...y puede conectarse directamente a ella. ESTO ES PELIGROSO.
docker compose exec web sh -c "nc -zv -w 3 db 5432" 2>&1 | tail -1

# la web también llega a la API (esto sí es legítimo)
docker compose exec web wget -qO- http://api:8000/ping
```

```text
: 172.18.0.4    db
db (172.18.0.4:5432) open
API viva
```

**El problema, en una frase:** no hay segmentación. Y sin segmentación no hay
forma de decir *"solo la API tiene derecho a hablar con la DB"*. Cualquier
servicio comprometido alcanza a todos los demás.

> **Pregunta para pensar:** la web **debería** poder hablar con la API
> (`web → api`), pero **no** con la base de datos (`web ↛ db`). Si las dos
> cosas son "conexiones entre contenedores", ¿cómo distinguimos una legítima de
> una peligrosa? Con **subredes distintas**.

---

## 5. Paso 3 — Segmentar (`front`/`back` + `internal` + DNS)

### 5.1 El diff

```diff
 services:
+  dns:
+    image: strm/dnsmasq
+    volumes: [ ./dnsmasq.conf:/etc/dnsmasq.conf:ro ]
+    networks:
+      front: { ipv4_address: 172.28.10.53 }
+
   web:
     image: nginx:alpine
+    networks:
+      front: { ipv4_address: 172.28.10.10 }
+
   api:
     build: ./api
+    networks:
+      front: { ipv4_address: 172.28.10.20 }
+      back:  { ipv4_address: 172.28.20.10 }   # ← el puente

   db:
     image: postgres:15-alpine
+    networks:
+      back: { ipv4_address: 172.28.20.20 }     # ← solo en back

 networks:
+  front:
+    driver: bridge
+    ipam:
+      config:
+        - subnet: 172.28.10.0/24
+  back:
+    driver: bridge
+    internal: true          # ← sin salida a Internet
+    ipam:
+      config:
+        - subnet: 172.28.20.0/24
```

Los tres cambios que hacen el trabajo:

1. **Cada servicio se conecta a redes explícitas.** `web` solo a `front`, `db`
   solo a `back`, y `api` a **las dos** (es el puente).
2. **`internal: true` en `back`.** Sin gateway ni NAT hacia Internet.
3. **Un DNS propio** (`dnsmasq`) que publica nombres estables del dominio.

```bash
docker compose down --remove-orphans
docker compose -f docker-compose.segmentado.yml up -d
docker compose -f docker-compose.segmentado.yml ps
```

### 5.2 Verificar la segmentación

```bash
COMPOSE="docker compose -f docker-compose.segmentado.yml"

# 1) web -> db POR NOMBRE: ya no resuelve (la DB vive solo en 'back')
$COMPOSE exec web getent hosts db            # sin salida

# 2) web -> db POR IP: prueba de RUTEO, no de DNS. Debe fallar por timeout.
$COMPOSE exec web sh -c "nc -z -w 3 172.28.20.20 5432"; echo "exit=$?"

# 3) api -> db: el único puente, sí conecta
$COMPOSE exec api python -c \
  "import socket as s; s.create_connection(('172.28.20.20',5432),3); print('API alcanza la DB')"

# 4) DNS interno: los 3 nombres
$COMPOSE exec web nslookup web.local 172.28.10.53
$COMPOSE exec web nslookup api.local 172.28.10.53
$COMPOSE exec web nslookup db.local  172.28.10.53
```

```text
API alcanza la DB
Name:      web.local
Address 1: 172.28.10.10
Name:      api.local
Address 1: 172.28.10.20
Name:      db.local
Address 1: 172.28.20.20
```

> **Dos mecanismos de DNS conviviendo:** el embebido de Docker (`127.0.0.11`)
> resuelve nombres de **servicio** (`web`, `api`, `db`); el `dnsmasq` propio
> (`.53`) resuelve los **nombres del dominio** (`web.local`, `api.local`,
> `db.local`).

> **Truco de la API:** la web no puede tocar la DB, pero sí pedirle a la API
> que lo compruebe *por ella*:
>
> ```bash
> $COMPOSE exec web wget -qO- http://api:8000/db
> # {"db":"alcanzable","host":"172.28.20.20","port":5432}
> ```
> Ese es el patrón de un **servicio mediado**: el frontend nunca habla con la
> base de datos; habla con la API.

---

## 6. Verificación automática

```bash
chmod +x verificar.sh
./verificar.sh
```

```text
 Resultado: 7 OK, 0 FALLO
```

Cubre: el estado del stack, `web` no resuelve `db`, `web` no alcanza la DB por
IP, `api` sí la alcanza, los tres nombres DNS resuelven y la web responde
HTTP 200.

---

## 7. 🔬 Laboratorio de experimentos

> **Esta es la parte más importante de la sesión.** Hasta ahora seguiste un
> roteiro. Ahora **tú** cambias el `docker-compose.yml` y observas qué pasa.
> Un contenedor de red se aprende tocándolo y rompiéndolo.

### Cómo trabajar con los experimentos

```bash
# 1) parte de una base limpia
docker compose -f docker-compose.segmentado.yml down -v --remove-orphans
cp docker-compose.segmentado.yml /tmp/compose.bak     # respaldo manual

# 2) edita el archivo (nano, vim, VS Code...)
#    y observa el cambio:
git diff                                # si clonaste con git
diff /tmp/compose.bak docker-compose.segmentado.yml

# 3) aplica y comprueba
docker compose -f docker-compose.segmentado.yml up -d

# 4) al terminar, vuelve al estado original
cp /tmp/compose.bak docker-compose.segmentado.yml
#   (o, si usas git: git checkout -- docker-compose.segmentado.yml)
docker compose -f docker-compose.segmentado.yml down -v --remove-orphans
```

Todos los comandos de abajo usan el alias:

```bash
COMPOSE="docker compose -f docker-compose.segmentado.yml"
```

---

### E1 · Publica la DB y descubre que no basta

**Cambia** — en el servicio `db`, añade:

```yaml
    ports: ["5432:5432"]
```

**Prueba**

```bash
$COMPOSE up -d
nc -z -w 3 localhost 5432 ; echo "exit=$?"
```

**Qué esperas** → **NO conecta** (`exit=1`). Y no es un fallo del experimento:
la DB vive en una red `internal: true`, y esa opción **también corta el NAT
hacia el host**, así que el mapeo de puerto se ignora en silencio.

```bash
docker inspect db-srv --format '{{json .NetworkSettings.Ports}}'
# {"5432/tcp":null}   <- configurado, pero no publicado
```

**Ahora hazlo de verdad** — quita también `internal: true` de la red `back`:

```bash
$COMPOSE up -d
nc -z -w 3 localhost 5432 && echo "AHORA SÍ: el perímetro está roto"
```

**Qué aprendes** → publicar un puerto son **dos** condiciones, no una:
`ports:` en el YAML **y** que el contenedor tenga camino de salida al host.
`internal: true` neutraliza la primera. Por eso el `ports:` de la DB es
peligroso: en cuanto publicas, expones la base de datos a toda la red donde
esté el host.

---

### E2 · Quita `internal: true` y mide exactamente qué se pierde

**Cambia** — borra la línea `internal: true` de la red `back`.

**Prueba**

```bash
# ¿La DB sale a Internet?
$COMPOSE exec db ping -c1 -W3 8.8.8.8

# ¿Ahora la web sí alcanza la DB?
$COMPOSE exec web sh -c "nc -z -w 3 172.28.20.20 5432"; echo "exit=$?"
```

**Qué esperas**

- La DB **sí** sale a Internet (`1 packets transmitted, 1 packets received`).
- La web **sigue sin** alcanzar la DB (`exit=1`).

**Qué aprendes** → `internal: true` controla el **egress** (la salida a
Internet), **no** el aislamiento entre contenedores. El aislamiento lo da la
**pertenencia** a la red. Vuelve a poner `internal: true` y comprueba que la DB
vuelve a dar `ping: sendto: Network unreachable`.

---

### E3 · Mete `web` dentro de `back`

**Cambia** — en `web`, dale las dos redes:

```yaml
    networks:
      front: { ipv4_address: 172.28.10.10 }
      back:  { ipv4_address: 172.28.20.10 }
```

**Prueba**

```bash
$COMPOSE up -d
$COMPOSE exec web sh -c "nc -z -w 3 172.28.20.20 5432" && echo "CONECTA"
$COMPOSE exec web getent hosts db
```

**Qué esperas** → **conecta**, y además `db` ahora **resuelve por nombre**
(`172.28.20.20  db`).

**Qué aprendes** → la segmentación no es una propiedad de la red: es una
decisión de **dónde conectas cada servicio**. Una sola línea de más y el
perímetro se deshace.

---

### E4 · Deja a la API sin `back` (ya no es el puente)

**Cambia** — en `api`, quita la red `back`:

```yaml
    networks:
      front: { ipv4_address: 172.28.10.20 }
```

**Prueba**

```bash
$COMPOSE up -d
$COMPOSE exec web curl -s -w " [HTTP %{http_code}]\n" http://api:8000/db
```

**Qué esperas** → **HTTP 503** y el cuerpo:

```text
{"db":"inalcanzable","error":"timed out","host":"172.28.20.20","port":5432} [HTTP 503]
```

> La API no se cae: sigue viva y **respondiendo**. Lo que cambió es que ya no
> tiene camino hacia la DB, y su endpoint `/db` lo dice con un 503 en vez de un
> 200.

**Qué aprendes** → la API es el **único autorizado** a hablar con los datos.
Sin su interfaz en `back`, nadie llega a la DB. Por eso la API puede tener dos
redes y la DB **no**: la API es el mediador controlado, la DB es el recurso
protegido.

---

### E5 · Cambia la IP de `web` y olvida el DNS

**Cambia** — en `web`, `ipv4_address: 172.28.10.10` → `172.28.10.11`
(y **no** toques `dnsmasq.conf`).

**Prueba**

```bash
$COMPOSE up -d
$COMPOSE exec web hostname -i                        # IP real
$COMPOSE exec web nslookup web.local 172.28.10.53    # lo que dice el DNS
```

**Qué esperas**

```text
172.28.10.11          <- la IP real
Address: 172.28.10.10 <- la IP vieja, desincronizada
```

**Qué aprendes** → `dnsmasq.conf` es una **copia manual** de la verdad. Las IPs
fijas y el DNS viven en dos sitios distintos y se desincronizan solos. Arregla
el `dnsmasq.conf` y comprueba que vuelve a cuadrar.

---

### E6 · Cambia la subred de `back`

**Cambia** — en la red `back`, `subnet: 172.28.20.0/24` → `172.28.30.0/24`
(sin tocar las `ipv4_address`).

**Prueba**

```bash
$COMPOSE up -d
```

**Qué esperas** → Compose se niega, con un mensaje explícito:

```text
Error response from daemon: invalid config for network lab_back:
invalid endpoint settings: no configured subnet contains IP address 172.28.20.10
```

**Arreglo** → actualiza **las tres** cosas: el `subnet`, el `ipv4_address` de
`db` (y de `api`) y el `dnsmasq.conf`.

**Qué aprendes** → la IPAM es determinista: Compose no "reparte lo que queda",
reserva exactamente lo que le pides. Los rangos de subred son una **decisión de
diseño** (VLAN + enrutamiento en el mundo real), no un detalle.

---

### E7 · Escala la API (y descubre por qué no se puede)

**Prueba**

```bash
$COMPOSE up -d --scale api=2
```

**Qué esperas** → falla, y Compose te da las dos pistas por separado:

```text
WARNING: The "api" service is using the custom container name "api-srv".
Docker requires each container to have a unique name. Remove the custom name to scale the service

Exited with code 1
```

Quita **solo** el `container_name` y lo intenta otra vez: ahora el error es
explícito sobre el segundo obstáculo:

```text
Error response from daemon: failed to set up container networking: Address already in use
```

**Arreglo** → en `api`, quita el `container_name` **y** las `ipv4_address`
fijas, dejándolo con redes dinámicas:

```yaml
  api:
    build: ./api
    networks: [front, back]
```

**Prueba otra vez**

```bash
$COMPOSE up -d --scale api=2
$COMPOSE exec web nslookup api.
```

**Qué esperas** → dos contenedores (`lab-api-1`, `lab-api-2`) con IPs
dinámicas, y el DNS devuelve **las dos**:

```text
Name: api
Address: 172.28.10.2
Name: api
Address: 172.28.10.3
```

**Qué aprendes** → **IP fija = una sola réplica.** Para escalar, la IP debe ser
dinámica y el nombre de servicio debe resolverse a varias direcciones. Es el
mecanismo de balanceo de Docker Compose: round-robin **en el DNS**.

---

### E8 · Convierte la web en un proxy real

Hasta ahora la web es un `nginx` que sirve su página de bienvenida: el flujo
`web → api` no está cableado. Vamos a cablearlo.

**Crea** `nginx.conf`:

```nginx
server {
    listen 80;
    location / {
        proxy_pass http://api:8000;
    }
}
```

**Cambia** — en `web`, añade:

```yaml
    volumes: [ ./nginx.conf:/etc/nginx/conf.d/default.conf:ro ]
```

**Prueba**

```bash
$COMPOSE up -d
curl -s http://localhost:8080/ping
curl -s http://localhost:8080/db
```

**Qué esperas**

```text
API viva
{"db":"alcanzable","host":"172.28.20.20","port":5432}
```

**Qué aprendes** → así se ve de verdad la cadena `web → api → db`, con la web
**sin acceso directo** a la base de datos. Fíjate en que `proxy_pass` usa el
nombre `api`: el `nginx` resuelve ese nombre con el **DNS embebido de Docker**,
sin que tengas que saber la IP. Y si escalas la API (E7), el nginx sigue
funcionando sin tocar nada.

---

### E9 · `down` no es lo mismo que `down -v`

**Prueba**

```bash
docker volume ls | grep pgdata     # antes
$COMPOSE down                       # apaga, conserva los datos
docker volume ls | grep pgdata     # sigue ahí
$COMPOSE up -d
$COMPOSE down -v                    # borra también el volumen
docker volume ls | grep pgdata     # desapareció
```

**Qué aprendes** → `down` **apaga** el stack; `down -v` **destruye los datos**.
Elegir bien entre `restart`, `down` y `down -v` es una decisión de producción:
un `down -v` en el script de arranque de un servidor borra la base de datos de
producción.

---

### Retos abiertos

Para quien quiera más (no son obligatorios):

1. **Tercera red `dmz`:** añade una red `dmz` (`172.28.30.0/24`) y un servicio
   `proxy`. ¿Qué servicio debe tener interfaz en las tres redes y por qué?
2. **Túnel SSH a la DB sin publicarla:** desde el host,
   `ssh -L 5432:172.28.20.20:5432 usuario@localhost` y conecta tu cliente a
   `localhost:5432`. Acceso controlado sin romper la segmentación.
3. **Documenta el fallo:** captura el *timeout* de `web → db` por IP y explica
   en tres líneas por qué **no** es un "connection refused".

---

## 8. Errores frecuentes

| Síntoma | Causa | Solución |
|---------|-------|----------|
| `web` SÍ alcanza la DB | `web` y `db` comparten red (o la DB publica `ports:`) | saca a `web` de `back`; revisa que la DB no publique puertos |
| `web` sí sale a Internet | `back` sin `internal: true` | vuelve a poner `internal: true` en `back` |
| Publicaste la DB y **no** abre el puerto | la DB está en una red `internal: true` (sin NAT al host) | quita `internal: true` o mueve la DB a una red con salida |
| Los nombres DNS no resuelven | la IP del servicio ≠ la IP en `dnsmasq.conf` | sincroniza las `ipv4_address` y `dnsmasq.conf` |
| `no configured subnet contains IP address` | cambiaste una subred sin actualizar las `ipv4_address` | actualiza subred + IPs + `dnsmasq.conf` |
| `Address already in use` al escalar | hay una `ipv4_address` fija en el servicio | quítala para poder tener varias réplicas |
| `port is already allocated` (8080) | otro stack ocupa el puerto | `docker compose down` en el otro |
| `network ... already exists` / solape de subred | quedó otra sesión levantada | `docker compose down -v` antes de subir |
| `nc: bad address` | el **nombre** no resuelve desde esa red (p. ej. `db` visto desde `front`) | prueba por IP: `nc -z -w 3 172.28.20.20 5432` |
| `nc` se cuelga | `nc` de busybox sin `-w` | usa siempre `nc -z -w 3 <ip> <puerto>` |
| `Connection refused` en vez de *timeout* | hay ruta pero nadie escucha en ese puerto | revisa que pruebes la IP y el puerto correctos |
| `./verificar.sh: Permission denied` | el script no es ejecutable | `chmod +x verificar.sh` |
| `pkill: not found` | la imagen `python:3.11-slim` no trae `procps` | usa `python -c "import os,signal; os.kill(1, signal.SIGINT)"` |

---

## 9. Limpieza

```bash
docker compose -f docker-compose.segmentado.yml down -v --remove-orphans
```

> Baja el stack antes de levantar el de otra sesión: todas usan
> `172.28.10.0/24` y `172.28.20.0/24`.

---

## 10. Entregable de la sesión

- [ ] `docker-compose.segmentado.yml` con `front`/`back` (`back` con
      `internal: true`) + DNS.
- [ ] Pruebas de segmentación: `web ↛ db` (por nombre **y** por IP) y
      `api → db` OK.
- [ ] `nslookup` de `web.local`, `api.local` y `db.local`.
- [ ] Salida de `./verificar.sh` (**7 OK, 0 FALLO**).
- [ ] **Al menos un experimento** del [laboratorio](#7--laboratorio-de-experimentos)
      documentado: qué cambiaste, qué viste y qué concluiste.
- [ ] Respuestas a las preguntas 1-4 de [SESION-1.md](../SESION-1.md).
