# Phenyx Health — Instalación en hospital

Este paquete instala la plataforma **Phenyx Health** (frontend + backend + rodaskernel + Postgres opcional) en un servidor del hospital usando Docker Compose. Las imágenes se descargan desde el registro privado de AWS ECR con las credenciales que te hemos facilitado.

> **Importante:** sigue los pasos **en orden**. El único paso automatizado es la generación del `docker-compose.yml`; todo lo demás son comandos que tú ejecutas y revisas.

---

## Qué vas a instalar

Todo el sistema corre en **una sola máquina** del hospital (el servidor Docker). Los cuatro servicios (`phenyxfrontend`, `phenyxback`, `rodaskernel` y `phenyxdb`) son contenedores en la misma red interna de Docker Compose. Desde fuera **solo se expone el puerto del frontend**; el resto de servicios no son alcanzables desde la red del hospital.

El navegador de cada usuario habla únicamente con el frontend. Nginx (dentro del contenedor del frontend) sirve la SPA y actúa como proxy inverso: todas las llamadas a `/api/*` las redirige al backend por la red interna de Docker. Así el usuario ve un único origen HTTP(S) y no hay CORS entre navegador y backend.

```
  Navegador del usuario (PC del hospital)
       │
       │ http(s)    (única URL pública: la del frontend)
       ▼
┌──────────────────────────────────────────────────────────┐
│  Servidor Docker del hospital                            │
│                                                          │
│   phenyxfrontend ──► phenyxback ──┬─► rodaskernel        │
│   (FRONTEND_PORT)      (interno)  │                      │
│        nginx                      └─► phenyxdb           │
│    /api/ → phenyxback:8080            o BD propia *      │
│                                                          │
│   Red interna de Docker Compose — nada sale al host      │
└──────────────────────────────────────────────────────────┘

  * Si usas BD propia del hospital, `phenyxdb` no se despliega y
    `phenyxback` se conecta a tu servidor Postgres por la red del
    hospital (tu responsabilidad de red/firewall).
```

Solo `phenyxfrontend` publica un puerto en el host (`FRONTEND_PORT`). `phenyxback`, `rodaskernel` y la BD Postgres incluida **no publican puertos en el host**: solo son accesibles desde dentro de la red interna de Docker Compose (el frontend alcanza al backend como `phenyxback:8080`).

---

## Requisitos

- **Docker 24+** y **Docker Compose v2** (`docker compose`, no `docker-compose`).
- **AWS CLI v2** — https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html
- Conectividad saliente HTTPS a `*.amazonaws.com`.
- Un puerto libre en el host: por defecto `80` (frontend). El generador te deja elegir otro en el **Paso 1** si está ocupado. Backend, `rodaskernel` y Postgres incluido no se publican y no consumen puertos del host.

---

## Datos que te hemos facilitado

Recíbelos por el canal seguro acordado y tenlos a mano durante la instalación:

| Dato | Valor |
| --- | --- |
| `AWS_ACCESS_KEY_ID` | (te lo hemos enviado) |
| `AWS_SECRET_ACCESS_KEY` | (te lo hemos enviado) |
| Región | `eu-west-1` |
| Registro | `471112885966.dkr.ecr.eu-west-1.amazonaws.com` |

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

- **Base de datos** — elige entre:
  - **Incluida** (Postgres en un contenedor): la opción por defecto, para piloto/preproducción. No se publica puerto en el host; si necesitas conectarte con un cliente SQL, ver la sección **Conectarse a la BD incluida desde fuera**.
  - **Propia**: te pedirá `DB_HOST`, `DB_PORT`, `DB_NAME`, `DB_USER`, `DB_PASS`. En ese caso el `docker-compose.yml` **no** incluirá el servicio `phenyxdb`.

El script solo **crea el fichero**. No arranca nada todavía.

---

## Paso 2 — Login en ECR

Copia y pega el bloque correspondiente a tu sistema, sustituyendo los placeholders por las credenciales que te facilitamos.

> **Token temporal:** el `docker login` en ECR genera un token que dura **12 horas**. Si un `docker pull` o `docker compose up` falla con `no basic auth credentials`, repite este paso.

**Windows (PowerShell):**
```powershell
$env:AWS_ACCESS_KEY_ID="AKIA..."
$env:AWS_SECRET_ACCESS_KEY="..."
$env:AWS_DEFAULT_REGION="eu-west-1"
aws ecr get-login-password --region eu-west-1 | docker login --username AWS --password-stdin 471112885966.dkr.ecr.eu-west-1.amazonaws.com
```

**Linux / macOS (bash):**
```bash
export AWS_ACCESS_KEY_ID="AKIA..."
export AWS_SECRET_ACCESS_KEY="..."
export AWS_DEFAULT_REGION="eu-west-1"
aws ecr get-login-password --region eu-west-1 | docker login --username AWS --password-stdin 471112885966.dkr.ecr.eu-west-1.amazonaws.com
```

Debes ver `Login Succeeded`. Al terminar la sesión, borra las variables de tu terminal:

```bash
unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_DEFAULT_REGION   # Linux/macOS
```
```powershell
Remove-Item Env:AWS_ACCESS_KEY_ID, Env:AWS_SECRET_ACCESS_KEY, Env:AWS_DEFAULT_REGION   # Windows
```

---

## Paso 3 — Arrancar el sistema

```bash
docker compose up -d
docker compose ps
```

`docker compose ps` debe mostrar los servicios con estado `Up` (o `running`):

- `phenyx-frontend`, `phenyx-backend`, `phenyx-rodaskernel`, y
- `phenyx-db` **solo** si elegiste BD incluida.

> **¿Necesitas cambiar el puerto del frontend, el `JWT_SECRET` o la configuración de la base de datos?** Vuelve a ejecutar `install.sh` / `install.ps1` (el generador guarda un backup automático del `docker-compose.yml` anterior) y luego haz `docker compose up -d` para aplicar la nueva configuración. La contraseña del usuario admin **no** se puede cambiar por esta vía una vez creado el usuario: hazlo desde la propia aplicación.

---

## Paso 4 — Verificación

1. Abre desde un navegador la URL del frontend (el `<host>:<puerto-host>` que expusiste para `phenyxfrontend`). Debe cargar la aplicación.
2. Comprueba que el frontend habla con el backend: abre la consola del navegador (F12 → Network) y verifica que las peticiones a `/api/...` (mismo host y puerto que el frontend) devuelven `200`.
3. Revisa los logs del backend:
   ```bash
   docker compose logs -f phenyxback
   ```
   No debe haber errores de conexión a la base de datos.

---

## Actualizar a una nueva versión

Cuando publiquemos una nueva versión de las imágenes:

1. Repite el **Paso 2 (Login en ECR)** — el token anterior habrá caducado.
2. Descarga las nuevas imágenes y recrea los contenedores:
   ```bash
   docker compose pull
   docker compose up -d
   docker compose ps
   ```

No hace falta volver a ejecutar `install.sh` salvo que quieras cambiar algún dato (URL pública, contraseña de BD, etc.).

---

## Base de datos propia

Si elegiste **BD propia** en el Paso 1:

- El `docker-compose.yml` no incluye el servicio `phenyxdb` ni lo referencia en el `depends_on` del backend.
- El usuario SQL que proporcionaste necesita privilegios para **crear tablas e índices** en la base de datos indicada (o equivalente; el esquema lo aplica el backend al arrancar).
- Si la base de datos ya contiene datos de una instalación previa, contáctanos antes de arrancar: puede requerir migración.

---

## Troubleshooting

| Error | Causa | Solución |
| --- | --- | --- |
| `no basic auth credentials` al hacer `pull` / `up` | Token ECR caducado (12 h) | Repetir **Paso 2** |
| `port is already allocated` al `up` | Puerto del host ocupado | Re-ejecutar `install.sh` / `install.ps1` y responder con otro puerto |
| `service "phenyxback" depends on undefined service "phenyxdb"` | Bloque `depends_on` incoherente | Re-ejecutar `install.sh` eligiendo de nuevo el tipo de BD |
| Frontend carga pero `/api/...` devuelve 502 | El contenedor `phenyxback` no está levantado o falló al arrancar | `docker compose ps` y `docker compose logs phenyxback` |
| Backend con errores de conexión a BD | Credenciales / host / puerto erróneos, o firewall | Comprobar con `psql` desde el host Docker antes de reintentar |
| `aws: command not found` | Falta AWS CLI v2 | Instalar desde https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html |
| `docker compose: 'compose' is not a docker command` | Docker Compose v1 | Actualizar a Docker Engine reciente (incluye Compose v2) |

Comandos de diagnóstico útiles:

```bash
docker compose config          # valida el YAML generado
docker compose logs -f         # logs en vivo de todos los servicios
docker compose logs phenyxback  # logs solo del backend
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

- Las credenciales AWS **no deben** quedar persistidas en `.env`, scripts, ni en el historial de shell. Ciérralas con `unset` / `Remove-Item Env:...` o cierra la terminal tras instalar/actualizar.
- Si aceptaste la contraseña de BD autogenerada por `install.sh`, anótala en tu gestor de secretos: está dentro del `docker-compose.yml`.
- La contraseña del **usuario admin inicial** (`DEFAULT_USER_PASSWORD`) queda **en claro dentro del `docker-compose.yml`**. Solo se usa para crear el admin la primera vez; cambiarla después en el `docker-compose.yml` no cambia la contraseña del usuario ya creado (eso se hace desde la aplicación). Cambia la contraseña del admin desde la aplicación tras el primer login y protege el fichero `docker-compose.yml` (permisos restrictivos, no subirlo a repositorios).
- Cambia el `JWT_SECRET` si por cualquier motivo dejó de ser secreto (re-ejecuta `install.sh`).

---

## Desinstalación

```bash
docker compose down -v       # detiene y borra contenedores y volúmenes
rm -rf phenyx-db-data phenyx-rodaskernel   # borra datos persistentes (si existen)
```

> `down -v` elimina también los datos de la BD incluida. Si usaste **BD propia**, sus datos **no** se tocan.
