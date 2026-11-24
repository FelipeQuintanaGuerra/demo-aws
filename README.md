# Demo: despliegue automático en AWS

Repositorio de la demo de la presentación **"Despliegue Automático en AWS"**.
Una API en Lambda que se despliega sola, con corte canario y rollback automático,
cada vez que se hace `git push`.

```
git push ─▶ CodePipeline ─▶ CodeBuild (tests + empaquetar) ─▶ CloudFormation/SAM ─▶ CodeDeploy (canario) ─▶ Lambda
            (diap. 6)       (diap. 7)                          (diap. 9)             (diap. 8 y 12)
```

## Qué hay en el repo

| Archivo | Para qué sirve | Diapositiva |
|---|---|---|
| `app/app.py` | La aplicación (una función Lambda con un mensaje y una versión) | 12 |
| `tests/test_app.py` | Tests unitarios que corre CodeBuild | 7 |
| `buildspec.yml` | Instrucciones del build: tests + empaquetado | 7 |
| `template.yaml` | Infraestructura de la **app**: Lambda, API, alias, canario, alarma | 9, 12 |
| `pipeline.yaml` | Infraestructura del **pipeline**: CodePipeline, CodeBuild, roles, bucket | 5, 6 |
| `scripts/trafico.sh` | Genera tráfico durante el canario | 12 |
| `scripts/limpiar.sh` | Borra todo al terminar | — |

## Requisitos

- Cuenta de AWS propia (ver nota sobre AWS Academy al final) y **AWS CLI** configurado (`aws configure`).
- Una cuenta de GitHub y un repositorio vacío para subir este código.
- Python 3.12 (solo si querés correr los tests en tu máquina).

Se asume la región `us-east-1`; cualquier otra sirve mientras uses la misma en todos los pasos.

## Preparación (hacerla ANTES del día de la demo)

### 1. Subir el código a GitHub

```bash
cd demo-aws
git init -b main
git add .
git commit -m "Version 1"
git remote add origin https://github.com/<TU_USUARIO>/<TU_REPO>.git
git push -u origin main
```

### 2. Crear la conexión de AWS a GitHub (se hace una sola vez, a mano)

1. Consola de AWS → **Developer Tools → Settings → Connections → Create connection**.
2. Proveedor **GitHub**, ponerle un nombre (ej. `demo-github`) y **Connect to GitHub**.
3. Autorizar en la ventana de GitHub e instalar la app en tu repo.
4. Verificar que el estado sea **Available** y copiar el **ARN** de la conexión.

### 3. Crear el pipeline

```bash
aws cloudformation deploy \
  --template-file pipeline.yaml \
  --stack-name demo-pipeline \
  --capabilities CAPABILITY_IAM \
  --parameter-overrides \
      GitHubOwner=<TU_USUARIO> \
      GitHubRepo=<TU_REPO> \
      ConnectionArn=<ARN_DE_LA_CONEXION>
```

Al terminar, el pipeline arranca solo con el código del paso 1. Entrá a
**CodePipeline → demo-pipeline-pipeline** y esperá a que las tres etapas queden en verde.
El primer despliegue crea la función desde cero, así que **no tiene canario**; tarda unos 3 minutos.

### 4. Obtener la URL de la app

```bash
aws cloudformation describe-stacks --stack-name demo-app \
  --query "Stacks[0].Outputs[?OutputKey=='ApiUrl'].OutputValue" --output text
```

Abrila en el navegador: debería responder `Hola desde AWS, versión 1`. Guardá esta URL.

### 5. Ensayo completo

Hacé la demo entera (abajo) al menos una vez, **incluyendo el rollback**, y grabá la pantalla.
Esa grabación es tu respaldo si el día de la demo falla internet o AWS.

## Guion de la demo (≈ 8 minutos)

Antes de empezar, tené abiertas estas pestañas: el repo en GitHub, la consola de CodePipeline,
la consola de CodeDeploy (Deployments) y la URL de la app. Una terminal lista para `trafico.sh`.

**1. Mostrar las piezas (2 min)**
- `buildspec.yml`: "esto es lo que hace CodeBuild: tests y empaquetado" (diap. 7).
- `template.yaml`: "acá se define la infraestructura como código: la función, la API y la política canario" (diap. 9 y 12).
- Consola de CodePipeline: las tres etapas Source → Build → Deploy (diap. 6).
- Abrir la URL de la app: `versión 1`.

**2. Despliegue normal con canario (4 min)**
1. En `app/app.py` cambiar `VERSION = "1"` por `VERSION = "2"`.
2. `git add . && git commit -m "Version 2" && git push`
3. En CodePipeline se dispara solo. Cuando pase Build y llegue a **Deploy**, correr en la terminal:
   ```bash
   ./scripts/trafico.sh <URL_DE_LA_APP>
   ```
4. Se ve la salida alternando entre versión 1 y 2: ese es el **10 % de tráfico** yendo a la versión nueva.
   En CodeDeploy → Deployments se ve el avance del despliegue.
5. A los 5 minutos de espera del canario, el tráfico pasa al 100 % a la versión 2 y el pipeline termina en verde.

> El canario espera 5 minutos. Mientras tanto, es el momento ideal para explicar la diapositiva 12
> (alias, versiones, traffic shifting) y la diapositiva 8 (estrategias).

**3. Rollback automático (opcional, +6 min, solo si hay tiempo)**
1. En `app/app.py` poner `FALLAR = True` y hacer push (`git commit -am "Rompo a proposito" && git push`).
2. Los tests **pasan** (el fallo solo aparece con un contexto real de Lambda): es la idea, un bug que los tests no atraparon.
3. En la etapa Deploy, correr `./scripts/trafico.sh <URL>`: parte de las respuestas serán `Internal Server Error`.
4. La alarma de CloudWatch salta y CodeDeploy **revierte solo**; el stack termina en `UPDATE_ROLLBACK_COMPLETE` y la app vuelve a responder bien.

Mensaje a cerrar: *"el despliegue falló, pero el 90 % de los usuarios nunca lo notó, y nadie tuvo que intervenir"*.

## Después de la demo: borrar todo

```bash
./scripts/limpiar.sh
```

Y borrar a mano la conexión a GitHub (Developer Tools → Settings → Connections).
Si se olvidan, los costos son mínimos (centavos), pero conviene dejarlo limpio.

## Problemas frecuentes

| Síntoma | Causa probable |
|---|---|
| La etapa Source falla | La conexión a GitHub no está en estado **Available**, o la app de GitHub no tiene acceso al repo |
| El build falla en `aws cloudformation package` | El rol de CodeBuild no llega al bucket: revisar que `pipeline.yaml` se desplegó completo |
| `trafico.sh` no muestra versión 2 | El canario todavía no empezó: esperar a que la etapa Deploy esté "In progress" |
| El rollback no se dispara | No hubo tráfico durante el canario: sin invocaciones no hay métrica de errores |
| El stack queda en `UPDATE_ROLLBACK_COMPLETE` sin que lo hayas provocado | Mirar el motivo en CloudFormation → Events y en CodeDeploy → Deployments |

## Notas

- **El rol de CloudFormation usa `AdministratorAccess`** para simplificar la demo. En un proyecto real
  se limita a los servicios que usa la aplicación (lo podés mencionar en la parte de buenas prácticas, diap. 14).
- **AWS Academy / Learner Lab:** estos entornos suelen restringir la creación de roles IAM y algunos servicios de
  Developer Tools. No pude verificar qué permite tu laboratorio; si `pipeline.yaml` falla por permisos, avisá y
  adapto la demo (por ejemplo, desplegar con `sam deploy` desde la terminal en lugar de usar CodePipeline).
