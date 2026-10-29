# Phenyx Health — Instalación en hospital

Este paquete instala la plataforma **Phenyx Health** (frontend + backend + rodaskernel + PostgreSQL opcional) en un servidor del hospital usando Docker Compose. Las imágenes se descargan desde el registro privado de Phenyx Health (`54.217.115.82:5000`) con las credenciales que te hemos facilitado.

> **Servidor sin internet:** el servidor no necesita internet para funcionar. Solo durante la instalación debe tener salida a **una única IP**, la del registro (`54.217.115.82`, puerto TCP `5000`). Una vez descargadas las imágenes (Paso 3) se puede cerrar toda la salida: el sistema arranca y funciona sin conexión.

> **Motor de base de datos:** Phenyx Health requiere **PostgreSQL** (13 o superior). Puedes usar la instancia Postgres que despliega este paquete en un contenedor, o apuntar a un servidor PostgreSQL propio del hospital. Otros motores (MySQL, MariaDB, SQL Server, Oracle…) no están soportados.

> **Importante:** sigue los pasos **en orden**. El único paso automatizado es la generación del `docker-compose.yml`; todo lo demás son comandos que tú ejecutas y revisas.

---

## Qué vas a instalar

Todo el sistema corre en **una sola máquina** del hospital (el servidor Docker). Los cuatro servicios (`phenyxhealthfrontend`, `phenyxhealthbackend`, `rodaskernel` y `phenyxdb`) son contenedores en la misma red interna de Docker Compose. Desde fuera **solo se expone el puerto del frontend**; el resto de servicios no son alcanzables desde la red del hospital.

El navegador de cada usuario habla únicamente con el frontend. Nginx (dentro del contenedor del frontend) sirve la SPA y actúa como proxy inverso: todas las llamadas a `/api/*` las redirige al backend por la red interna de Docker. Así el usuario ve un único origen HTTP(S) y no hay CORS entre navegador y backend.

```
  Navegador del usuario (PC del hospital)
       │
       │ http(s)    (único puerto público: el del frontend)
       ▼
┌──────────────────────────────────────────────────────────────────┐
│  Servidor Docker del hospital                                    │
│                                                                  │
│   phenyxhealthfrontend ──► phenyxhealthbackend ──┬─► rodaskernel │
│   (FRONTEND_PORT)          (interno)             │               │
│        nginx                                     └─► phenyxdb    │
│    /api/ → phenyxhealthbackend:8080                 o BD propia *│
│                                                                  │
│   Solo phenyxhealthfrontend publica puerto en el host;           │
│   el resto queda dentro de la red interna de Docker              │
└──────────────────────────────────────────────────────────────────┘

  * Si usas BD propia del hospital, `phenyxdb` no se despliega y
    `phenyxhealthbackend` se conecta a tu servidor Postgres por la
    red del hospital (tu responsabilidad de red/firewall).
```

Solo `phenyxhealthfrontend` publica un puerto en el host (`FRONTEND_PORT`). `phenyxhealthbackend`, `rodaskernel` y la BD Postgres incluida **no publican puertos en el host**: solo son accesibles desde dentro de la red interna de Docker Compose (el frontend alcanza al backend como `phenyxhealthbackend:8080`).

---

## Requisitos

- **Docker 24+** y **Docker Compose v2** (`docker compose`, no `docker-compose`), ya instalados: la instalación de Docker no se hace desde el registro.
- Durante la instalación, salida TCP al puerto `5000` de `54.217.115.82`. No hace falta DNS ni ningún otro destino.
- **Antes de empezar, comunícanos la IP pública con la que saldrá el servidor**: el registro solo acepta conexiones de las IPs que autorizamos.
- Un puerto libre en el host: por defecto `80` (frontend). El generador te deja elegir otro en el **Paso 1** si está ocupado. Backend, `rodaskernel` y Postgres incluido no se publican y no consumen puertos del host.

---

## Datos que te hemos facilitado

Recíbelos por el canal seguro acordado y tenlos a mano durante la instalación:

| Dato | Valor |
| --- | --- |
| Registro | `54.217.115.82:5000` |
| Usuario | (te lo hemos enviado) |
| Contraseña | (te la hemos enviado) |
| `registry-ca.crt` | Certificado de la autoridad que firma el registro (te lo hemos enviado). Cópialo al directorio de este paquete |

Estas credenciales sirven **solo** para descargar las imágenes Docker; no dan acceso a ningún otro recurso.

---

## Paso 1 — Generar el `docker-compose.yml`

Desde el directorio de este paquete, ejecuta el generador. Te hará unas preguntas y creará el `docker-compose.yml`.

**Linux / macOS:**
```bash
chmod +x install.sh
./install.sh
```

**Windows (PowerShell):**
```powershell
.\install.ps1
```

Preguntas que te hará:

- **Puerto del host (frontend)** — por defecto `80`. Cámbialo si está ocupado en esta máquina. Es el único puerto que los PCs del hospital necesitarán alcanzar. Backend, `rodaskernel` y Postgres no se publican: solo son accesibles desde dentro de Docker.

- **JWT secret** — por defecto se genera uno aleatorio fuerte; recomendado aceptarlo.

- **Usuario admin inicial** — nombre y contraseña con los que se creará el usuario administrador la **primera vez** que el backend arranque contra una base de datos vacía. Por defecto el nombre es `admin`.

  > **Aviso (creación única):** el usuario admin se crea **solo** cuando el backend encuentra la base de datos vacía. Una vez creado, volver a ejecutar `docker compose up -d` **no** vuelve a crearlo ni actualiza su contraseña, aunque cambies `DEFAULT_USER_NAME` o `DEFAULT_USER_PASSWORD` en el `docker-compose.yml`. A partir de ese momento, los cambios de usuario/contraseña se hacen **desde la propia aplicación**. Lo mismo aplica si apuntas a una BD propia que ya contiene usuarios: estas variables se ignoran.

  > **Aviso (contraseña en claro):** la contraseña que introduzcas queda **guardada en claro** dentro del `docker-compose.yml` generado (variable `DEFAULT_USER_PASSWORD`). Protege ese fichero (permisos restrictivos, copias de seguridad cifradas) y cambia la contraseña desde la aplicación tras el primer login.

- **Base de datos** — el backend **solo soporta PostgreSQL** (versión 13 o superior). Otros motores (MySQL, MariaDB, SQL Server, Oracle…) **no** son compatibles. Elige entre:
  - **Incluida** (Postgres en un contenedor): la opción por defecto, para piloto/preproducción. No se publica puerto en el host; si necesitas conectarte con un cliente SQL, ver la sección **Conectarse a la BD incluida desde fuera**.
  - **Propia**: un servidor **PostgreSQL** que mantiene el hospital. Te pedirá `DB_HOST`, `DB_PORT`, `DB_NAME`, `DB_USER`, `DB_PASS`. En ese caso el `docker-compose.yml` **no** incluirá el servicio `phenyxdb`.

  > **Aviso (credenciales de BD en claro):** los datos de conexión a la base de datos (`DB_HOST`, `DB_PORT`, `DB_NAME`, `DB_USER` y, en particular, `DB_PASS`) quedan **guardados en claro** dentro del `docker-compose.yml` generado, tanto si usas el Postgres incluido como si apuntas a un servidor propio del hospital. Protege el fichero (permisos restrictivos, copias de seguridad cifradas, no subirlo a repositorios) y, si usas BD propia, usa un usuario de BD con privilegios limitados a la base de datos de Phenyx Health.

El script solo **crea el fichero**. No arranca nada todavía.

---

## Paso 2 — Confiar en el registro y hacer login

A partir de aquí necesitas la salida a `54.217.115.82:5000` abierta.

El registro usa un certificado firmado por nuestra propia autoridad, así que primero hay que decirle a Docker que confíe en ella con el fichero `registry-ca.crt`. Después se hace `docker login`, que te pedirá el usuario y la contraseña que te facilitamos.

> Haz el login con **el mismo usuario** del sistema con el que vas a lanzar `docker compose`: Docker guarda la sesión en el perfil de ese usuario.

**Linux:**
```bash
sudo install -d -m 0755 /etc/docker/certs.d/54.217.115.82:5000
sudo install -m 0644 registry-ca.crt /etc/docker/certs.d/54.217.115.82:5000/ca.crt
docker login 54.217.115.82:5000
```

**Windows (PowerShell como administrador):**
```powershell
Import-Certificate -FilePath .\registry-ca.crt -CertStoreLocation Cert:\LocalMachine\Root
# Reinicia Docker (Docker Desktop: Restart) para que lea el certificado
docker login 54.217.115.82:5000
```

En **macOS** con Docker Desktop, copia el certificado a `~/.docker/certs.d/54.217.115.82:5000/ca.crt`, reinicia Docker Desktop y haz el mismo `docker login`.

Debes ver `Login Succeeded`.

---

## Paso 3 — Descargar las imágenes

```bash
docker compose pull
docker image ls
```

`docker compose pull` descarga del registro todas las imágenes, Postgres incluido. `docker image ls` debe listar las de `54.217.115.82:5000` (`phenyxhealthfrontend`, `phenyxhealthbackend` y `phenyxhealthrodaskernel`, más `postgres` si elegiste la BD incluida). Cuando termine sin errores, cierra la sesión del registro, que ya no hace falta:

```bash
docker logout 54.217.115.82:5000
```

**En este punto ya se puede cerrar la salida a internet del servidor.** Los pasos siguientes no necesitan conexión.

---

## Paso 4 — Arrancar el sistema

```bash
docker compose up -d
docker compose ps
```

`docker compose ps` debe mostrar los servicios con estado `Up` (o `running`):

- `phenyx-frontend`, `phenyx-backend`, `phenyx-rodaskernel`, y
- `phenyx-db` **solo** si elegiste BD incluida.

> **¿Necesitas cambiar el puerto del frontend, el `JWT_SECRET` o la configuración de la base de datos?** Vuelve a ejecutar `install.sh` / `install.ps1` (el generador guarda un backup automático del `docker-compose.yml` anterior) y luego haz `docker compose up -d` para aplicar la nueva configuración. La contraseña del usuario admin **no** se puede cambiar por esta vía una vez creado el usuario: hazlo desde la propia aplicación.

---

## Paso 5 — Verificación

1. Abre desde un navegador la URL del frontend (el `<host>:<puerto-host>` que expusiste para `phenyxhealthfrontend`). Debe cargar la aplicación.
2. Comprueba que el frontend habla con el backend: abre la consola del navegador (F12 → Network) y verifica que las peticiones a `/api/...` (mismo host y puerto que el frontend) devuelven `200`.
3. Revisa los logs del backend:
   ```bash
   docker compose logs -f phenyxhealthbackend
   ```
   No debe haber errores de conexión a la base de datos.

---

## Actualizar a una nueva versión

Cuando publiquemos una nueva versión de las imágenes:

1. Vuelve a abrir la salida a `54.217.115.82:5000` (puerto TCP `5000`). Si la IP pública del servidor ha cambiado, comunícanosla antes.
2. Haz `docker login 54.217.115.82:5000` como en el **Paso 2**. El certificado ya está instalado y no hay que repetirlo.
3. Descarga las nuevas imágenes, cierra la sesión y recrea los contenedores:
   ```bash
   docker compose pull
   docker logout 54.217.115.82:5000
   docker compose up -d
   docker compose ps
   ```
4. Vuelve a cerrar la salida a internet.

No hace falta volver a ejecutar `install.sh` salvo que quieras cambiar algún dato (puerto público, contraseña de BD, etc.).

---

## Base de datos propia

Si elegiste **BD propia** en el Paso 1:

- **Debe ser PostgreSQL** (13 o superior). El backend no soporta otros motores.
- El `docker-compose.yml` no incluye el servicio `phenyxdb` ni lo referencia en el `depends_on` del backend.
- El usuario SQL que proporcionaste necesita privilegios para **crear tablas e índices** en la base de datos indicada (o equivalente; el esquema lo aplica el backend al arrancar).
- Si la base de datos ya contiene datos de una instalación previa, contáctanos antes de arrancar: puede requerir migración.

---

## Troubleshooting

| Error | Causa | Solución |
| --- | --- | --- |
| `x509: certificate signed by unknown authority` | Docker no confía en el certificado del registro | Revisar que `registry-ca.crt` esté en la ruta del **Paso 2** (en Windows y macOS, reiniciar Docker después) |
| Timeout o `connection refused` contra `54.217.115.82:5000` | La salida al registro está cerrada, o no hemos autorizado la IP pública del servidor | Comprobar el firewall del hospital y confirmar con nosotros la IP de salida |
| `no basic auth credentials` o `unauthorized` al hacer `pull` | No hay sesión iniciada en el registro (después del Paso 3 se cierra a propósito) | Repetir el `docker login` del **Paso 2** |
| `up` intenta descargar y falla sin internet | Falta alguna imagen en local | Repetir el **Paso 3** con la salida abierta |
| `port is already allocated` al `up` | Puerto del host ocupado | Re-ejecutar `install.sh` / `install.ps1` y responder con otro puerto |
| `service "phenyxhealthbackend" depends on undefined service "phenyxdb"` | Bloque `depends_on` incoherente | Re-ejecutar `install.sh` eligiendo de nuevo el tipo de BD |
| Frontend carga pero `/api/...` devuelve 502 | El contenedor `phenyxhealthbackend` no está levantado o falló al arrancar | `docker compose ps` y `docker compose logs phenyxhealthbackend` |
| Backend con errores de conexión a BD | Credenciales / host / puerto erróneos, o firewall | Comprobar con `psql` desde el host Docker antes de reintentar |
| `docker compose: 'compose' is not a docker command` | Docker Compose v1 | Actualizar a Docker Engine reciente (incluye Compose v2) |

Comandos de diagnóstico útiles:

```bash
docker compose config          # valida el YAML generado
docker compose logs -f         # logs en vivo de todos los servicios
docker compose logs phenyxhealthbackend  # logs solo del backend
docker compose ps              # estado de los contenedores
```

---

## Conectarse a la BD incluida desde fuera

Por defecto, el servicio `phenyxdb` **no publica puerto en el host**: solo el backend (a través de la red interna de Docker) puede alcanzarlo. Si necesitas conectarte con un cliente SQL (pgAdmin, DBeaver, `psql`) para una operación puntual:

**Opción A — desde el propio servidor**, usando el cliente `psql` dentro del contenedor:

```bash
docker compose exec phenyxdb psql -U postgres -d postgres
```

**Opción B — publicar el puerto temporalmente**: edita el `docker-compose.yml` y añade un bloque `ports:` al servicio `phenyxdb` (por ejemplo `"5432:5432"`), luego `docker compose up -d`. Cuando termines, quita ese bloque y vuelve a hacer `docker compose up -d`.

---

## Seguridad

- La contraseña del registro **no debe** quedar en ficheros, scripts ni en el historial de shell: escríbela solo cuando la pida `docker login` y cierra la sesión con `docker logout` al terminar de descargar.
- Cierra la salida a `54.217.115.82:5000` en cuanto termines de instalar o actualizar.
- El `docker-compose.yml` generado contiene **en claro** tanto las **credenciales de la base de datos** (`DB_HOST`, `DB_PORT`, `DB_NAME`, `DB_USER`, `DB_PASS`) como la **contraseña del usuario admin inicial** (`DEFAULT_USER_PASSWORD`) y el `JWT_SECRET`. Protege el fichero con permisos restrictivos, no lo subas a repositorios y, si haces copias de seguridad del mismo, cífralas.
- Si aceptaste la contraseña de BD autogenerada por `install.sh`, anótala en tu gestor de secretos: solo queda dentro del `docker-compose.yml`.
- La contraseña del **usuario admin inicial** (`DEFAULT_USER_PASSWORD`) solo se usa para crear el admin la primera vez; cambiarla después en el `docker-compose.yml` **no** cambia la contraseña del usuario ya creado (eso se hace desde la aplicación). Cambia la contraseña del admin desde la aplicación tras el primer login.
- Cambia el `JWT_SECRET` si por cualquier motivo dejó de ser secreto (re-ejecuta `install.sh`).

---

## Desinstalación

```bash
docker compose down -v       # detiene y borra contenedores y volúmenes
rm -rf phenyx-db-data phenyx-rodaskernel   # borra datos persistentes (si existen)
```

> `down -v` elimina también los datos de la BD incluida. Si usaste **BD propia**, sus datos **no** se tocan.
