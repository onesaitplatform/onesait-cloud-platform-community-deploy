# Guía del Entorno de Prácticas - OnesaitPlatform

Este proyecto proporciona un entorno local empaquetado para realizar prácticas con **OnesaitPlatform** utilizando contenedores Docker en tu entorno de WSL2.

---

## 🛠️ Prerrequisitos de Software

Antes de iniciar, asegúrate de tener instalado en tu máquina:
1.  **Docker Desktop** (con la integración de WSL habilitada) o **Docker Engine** instalado directamente en tu distribución de WSL.
2.  **Docker Compose** (versión v2 o superior).
3.  **Git**.

> [!IMPORTANT]
> **Asignación de Memoria RAM:**
> OnesaitPlatform es un sistema robusto basado en microservicios Java/Spring Boot.
> - Si levantas el perfil **Completo**, necesitarás al menos **12 GB de RAM** libres para Docker/WSL.
> - Si usas los perfiles de **Grupo (Integración, Reportes o Analítica)**, el consumo se reduce drásticamente, permitiendo trabajar en ordenadores con **8 GB de RAM** en total.

---

## 🚀 Cómo Iniciar el Entorno (Estudiantes)

1.  Abre tu consola de WSL y navega a la carpeta del proyecto:
    ```bash
    cd ~/personal-projects/onesait-platform-deploy
    ```
2.  Ejecuta el script de despliegue:
    ```bash
    ./deploy.sh
    ```
3.  El script te solicitará dos cosas:
    *   **SERVER_NAME:** Presiona `Enter` para usar `localhost`.
    *   **Perfil de Trabajo:** Selecciona el número correspondiente a tu grupo para iniciar solo los módulos que necesitas.

El script se encargará automáticamente de generar los certificados SSL locales, configurar la persistencia, inicializar las bases de datos si es la primera vez y levantar los contenedores.

### 🛑 Cómo Detener el Entorno

Cuando termines de trabajar, puedes detener de forma limpia todos los contenedores de OnesaitPlatform y liberar memoria RAM ejecutando:
```bash
./stop.sh
```

---

## 👥 Cuentas de Acceso y Perfiles

Al finalizar el arranque, puedes abrir tu navegador en la siguiente dirección:
👉 **`https://localhost/controlpanel/`** *(Acepta la advertencia de certificado autofirmado en el navegador).*

### Estudiantes y Grupos de Trabajo

| Usuario | Contraseña | Rol / Grupo | Módulos Clave Asignados |
| :--- | :--- | :--- | :--- |
| `anyi` | `onesaitplatform` | Integración de Información | Control Panel, Dataflow (ETL), Flow Engine (Node-RED) |
| `fernando` | `onesaitplatform` | Integración de Información | Control Panel, Dataflow (ETL), Flow Engine (Node-RED) |
| `wesfalia` | `onesaitplatform` | Reporting y Negocio | Control Panel, Dashboard Engine (Visualización) |
| `kevin` | `onesaitplatform` | Reporting y Negocio | Control Panel, Dashboard Engine (Visualización) |
| `pamela` | `onesaitplatform` | Reporting y Negocio | Control Panel, Dashboard Engine (Visualización) |
| `isaias` | `onesaitplatform` | Analítica Predictiva | Control Panel, Notebooks (Jupyter integrado) |

### Profesor / Administrador
*   **Usuario:** `administrator` o `developer`
*   **Contraseña:** `onesaitplatform`

---

## 💾 Entrega de Prácticas (Estudiantes)

Para entregar tu trabajo, no debes subir los archivos binarios de la base de datos a Git (están ignorados automáticamente en el `.gitignore`).
La forma correcta de entregar tu trabajo es exportándolo de forma limpia desde la plataforma:

1.  Inicia sesión en la consola web con tu usuario.
2.  Ve al menú lateral y busca la opción **Herramientas de Desarrollo** (Development Tools) -> **Exportar/Importar Configuración** (Export/Import Configuration).
3.  Selecciona los elementos que has desarrollado en tu práctica (ontologías, dashboards, APIs, flujos, etc.).
4.  Exporta y descarga el archivo comprimido (`.zip` o `.json`).
5.  Entrega este archivo al profesor para su corrección.

---

## 🎓 Gestión de la Práctica (Para el Profesor)

Si deseas pre-configurar elementos de inicio para tus alumnos (por ejemplo, subir datos iniciales, crear APIs de ejemplo, etc.):

1.  Inicia el entorno usando el perfil **Completo / Profesor** (`1`).
2.  Accede como `administrator` a `https://localhost/controlpanel/` y realiza las configuraciones y cargas de datos deseadas.
3.  Cuando todo esté listo, ejecuta el script de respaldo en tu consola de WSL:
    ```bash
    ./backup.sh
    ```
    Esto creará archivos de respaldo en la carpeta `./db_seed/`.
4.  Realiza un commit y push de la carpeta `db_seed/` a tu repositorio Git.
5.  Cuando los alumnos clonen tu repositorio y ejecuten `./deploy.sh` por primera vez, el script importará automáticamente todo tu diseño inicial de la carpeta `db_seed/`.
