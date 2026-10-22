# Sesión 1 · Primer stack con Docker Compose: segmentación y DNS

> **Laboratorio N.º 14 — De la red real a la red virtual** · Unidad III · **Sesión 1 de 4** · 120 min

Este repositorio contiene los archivos de la **Sesión 1** del laboratorio. Es un
curso de **Redes de Computadoras** en el que Docker Compose es el *medio*: en
lugar de dibujar hosts en un papel, los **ejecutas** para ver la red funcionando
de verdad.

**Lo que construyes:** un stack `web` + `api` + `db` que pasa de una **red
plana** (insegura: todos se ven) a **dos subredes segmentadas** (`front` / `back`)
con **DNS interno**, y compruebas cada paso con comandos de red reales —
`getent`, `nc`, `nslookup` — no con la fe del YAML.

| Lo que aprendes | Cómo lo ve Compose | Cómo lo compruebas |
|---|---|---|
| Segmentación | dos `networks:` (`front`, `back`) | `web` no alcanza a `db` |
| Subredes y direccionamiento | `ipam.config` + `ipv4_address` | `172.28.10.x` vs `172.28.20.x` |
| Enrutamiento | `internal: true` (corta el *egress*) | `ping` a Internet desde la DB |
| DNS | `dnsmasq` en `172.28.10.53` | `nslookup web.local` |
| Puertos y NAT | `ports:` vs `expose:` | `curl localhost:8080` |

---

## 1. Descarga los archivos

### Opción A — Clonar el repositorio (recomendada)

```bash
git clone https://github.com/isacioutp/lab-8-docker-compose.git
cd lab-8-docker-compose/sesion-1
```

Ventaja: además de los archivos, queda el **historial de Git**, así que puedes
ver qué cambió en cada experimento con `git diff` y volver atrás con
`git checkout -- .`. Es la forma recomendada para esta sesión porque el
[Laboratorio de experimentos](sesion-1/README.md#7--laboratorio-de-experimentos) está pensado
para que modifiques el `docker-compose.yml` y luego lo deshagas.

> Si clonas por SSH en vez de HTTPS, cambia la URL por
> `git@github.com:isacioutp/lab-8-docker-compose.git`.

### Opción B — Descargar el ZIP

Sin Git instalado: en la página del repositorio → botón **Code** →
**Download ZIP**. Al descomprimir obtendrás una carpeta
`lab-8-docker-compose-main/`; entra en `sesion-1/`.

```bash
cd lab-8-docker-compose-main/sesion-1
```

### Opción C — Descargar un archivo suelto

Cada archivo se puede bajar suelto desde `raw.githubusercontent.com` (útil si
trabajas en una máquina sin permisos de escritura o sin Git):

```bash
# Ejemplo: bajarte solo el compose segmentado y el DNS
curl -O https://raw.githubusercontent.com/isacioutp/lab-8-docker-compose/main/sesion-1/docker-compose.segmentado.yml
curl -O https://raw.githubusercontent.com/isacioutp/lab-8-docker-compose/main/sesion-1/dnsmasq.conf
```

> No olvides el `api/` (código + `Dockerfile`) y el `verificar.sh`: son
> necesarios para levantar el stack.

### Opción D — Copiar la carpeta tal cual

Si ya tienes los archivos (los entregaste en clase, o los tienes en otro
directorio), solo copia la carpeta completa y a trabajar:

```bash
cp -r /ruta/al/material/sesion-1 ~/lab14/sesion-1
cd ~/lab14/sesion-1
```

> **Importante:** trabaja siempre **dentro** de la carpeta `sesion-1/`. Compose
> toma el nombre del proyecto del nombre de la carpeta y los comandos como
> `docker compose -f docker-compose.segmentado.yml` asumen que estás ahí.

---

## 2. Comprueba que tu entorno está listo

```bash
docker --version            # Docker Engine
docker compose version      # plugin "docker compose" (no el binario viejo)
```

Y que el puerto que usará la web esté libre:

```bash
(ss -ltn 2>/dev/null || netstat -ltn) | grep ':8080' && echo "OCUPADO" || echo "8080 libre"
```

---

## 3. Arranque en 30 segundos

```bash
cd sesion-1

# 1) red segmentada (el estado final de la sesión)
docker compose -f docker-compose.segmentado.yml up -d

# 2) ver la topología
docker compose -f docker-compose.segmentado.yml ps

# 3) pasar las 7 pruebas automáticamente
chmod +x verificar.sh
./verificar.sh            # -> Resultado: 7 OK, 0 FALLO
```

Si eso da `7 OK, 0 FALLO`, ya tienes el entorno de la Sesión 1 funcionando.

---

## 4. El paso a paso detallado

Todo el desarrollo —qué hace cada línea del YAML, cómo se rompe la red plana,
cómo se segmenta, cómo se verifica y **qué experimentos hacer para entender de
verdad cómo funciona**— está en:

### → **[`sesion-1/README.md`](sesion-1/README.md)**

Incluye:

- **Descarga de los archivos** (los 4 métodos, con comandos exactos)
- **Prerrequisitos** y comprobaciones previas
- **Paso 1** — el primer `docker compose up`, línea por línea
- **Paso 2** — el problema: en la red plana la web alcanza la base de datos
- **Paso 3** — segmentar: `front`/`back`, `internal: true` y DNS interno
- **Paso 4** — verificar (a mano y con script)
- **🔬 Laboratorio de experimentos** — 9 cambios guiados en el
  `docker-compose.yml` para que veas *qué cambia* y *por qué*
- Errores frecuentes, limpieza y entregable

---

## 5. La guía académica de la sesión

Si necesitas el desarrollo teórico, los objetivos formativos, los
**checkpoints** y las **preguntas evaluadas**:

### → **[`SESION-1.md`](SESION-1.md)**

---

## 6. Teoría de apoyo

Repaso ampliado de LAN, segmentación, subredes, DNS, puertos y NAT que sostiene
la sesión:

### → **[`TEORIA.md`](TEORIA.md)**

---

## 7. Reglas de la sesión

- **El entregable es el `docker-compose.yml`**, no capturas de pantalla sueltas.
- **Verifica siempre**: un YAML bonito no prueba nada; `getent`, `nc` y
  `nslookup` sí.
- **No publiques la DB**: en `db` jamás va un `ports:` (explica en la clase por
  qué el `ports:` solo no basta).
- **Un solo `up` debe reproduzca todo**: nada de `docker run` sueltos.
- **No subas credenciales**: la contraseña de la Sesión 1 es de práctica; en la
  Sesión 3 se migra a `secrets:`.

---

## Problemas frecuentes

| Síntoma | Solución rápida |
|---|---|
| `docker: command not found` | instala Docker Engine + el plugin `docker compose` |
| `port is already allocated` | otro stack ocupa el 8080 → `docker compose down` en el otro |
| `network ... already exists` | hay otra sesión levantada → `docker compose down -v` |
| `no configured subnet contains IP address` | cambiaste una subred sin actualizar las `ipv4_address` |
| `Address already in use` al escalar | hay una `ipv4_address` fija: quítala para poder escalar |
| `./verificar.sh: Permission denied` | `chmod +x verificar.sh` |

La tabla completa, con las causas, está en
[`sesion-1/README.md`](sesion-1/README.md#8-errores-frecuentes).
