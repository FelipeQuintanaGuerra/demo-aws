# Cómo funciona la demo

Es una demo de **CI/CD sobre AWS**: una API serverless que se despliega sola con cada `git push`.
Primero manda el 10 % del tráfico a la versión nueva (despliegue canario) y, si esa versión falla,
vuelve sola a la anterior (rollback automático).

## Idea general

Hay dos plantillas de CloudFormation, y conviene tenerlas separadas en la cabeza:

| Plantilla | Qué crea | Quién la despliega |
|---|---|---|
| `pipeline.yaml` | El pipeline: CodePipeline, CodeBuild, bucket S3, roles IAM | Vos, **una sola vez**, con `aws cloudformation deploy` |
| `template.yaml` | La aplicación: Lambda, API Gateway, alias, canario, alarma | El **pipeline**, en cada push |

O sea, armás el pipeline a mano una vez y desde ahí el pipeline se encarga de desplegar la app.

## Flujo de un `git push`

```
GitHub ──▶ Source ──▶ Build (CodeBuild) ──▶ Deploy (CloudFormation) ──▶ CodeDeploy ──▶ Lambda
```

1. **Source** (`pipeline.yaml`): una conexión de CodeConnections vigila la rama `main` del repo.
   Con cada push baja el código como ZIP y arranca el pipeline.
2. **Build** (`buildspec.yml`):
   - `pre_build`: corre los tests unitarios (`tests/test_app.py`). Si falla alguno, el pipeline se corta ahí.
   - `build`: `aws cloudformation package` sube el código de `app/` al bucket S3. Genera `packaged.yaml`,
     que es `template.yaml` con `CodeUri` apuntando a S3.
3. **Deploy**: CloudFormation crea o actualiza el stack `demo-app` a partir de `packaged.yaml`.
   Usa un rol con `AdministratorAccess`, lo que está bien para la demo pero no en producción.
4. **CodeDeploy** hace el corte canario (ver abajo).

## La app (`app/app.py`)

Es una Lambda mínima que responde `{"mensaje": "Hola desde AWS, versión 1", "version": "1"}`.
Tiene dos "perillas" para la demo:

- **`VERSION`**: la cambiás y hacés push para mostrar un despliegue normal.
- **`FALLAR`**: la ponés en `True` para provocar un error. El truco está en que solo falla si
  `context is not None`. En los tests el handler se llama con `context=None`, así que **los tests pasan**,
  pero en Lambda real el context existe y explota. Así se simula un bug que los tests no detectan
  y llega a producción.

## Cómo funcionan el canario y el rollback (`template.yaml`)

- **`AutoPublishAlias: live`**: en cada despliegue SAM publica una versión nueva de la Lambda,
  que no se puede modificar, y la API Gateway siempre invoca al alias `live`.
- **`DeploymentPreference: Canary10Percent5Minutes`**: SAM crea una aplicación de CodeDeploy que mueve
  el alias de a poco. Primero 90 % a la versión vieja y 10 % a la nueva, espera 5 minutos y después
  pasa el 100 % a la nueva.
- **`CanaryErrorsAlarm`**: una alarma de CloudWatch sobre la métrica `Errors`, filtrada por
  `ExecutedVersion` para que mire **solo la versión nueva**. Con un solo error en un período de 60 s
  se dispara (umbral > 0).
- Si la alarma salta durante esos 5 minutos, CodeDeploy devuelve el alias a la versión anterior.
  CloudFormation marca la actualización como fallida y el stack queda en `UPDATE_ROLLBACK_COMPLETE`.

**Ojo con el primer despliegue:** como la función todavía no existe, no hay versión anterior con la
cual repartir el tráfico, así que ese despliegue no tiene canario.

## Los scripts

- **`trafico.sh`**: un `curl` cada 0,5 s contra la API. Cumple dos funciones:
  - **Visual**: muestra la alternancia entre v1 y v2, más o menos 1 de cada 10 respuestas.
  - **Funcional**: sin invocaciones no hay métricas, y sin métricas la alarma nunca salta.
    `TreatMissingData: notBreaching` la deja en OK.
- **`limpiar.sh`**: borra el stack de la app, vacía el bucket (CloudFormation no borra buckets con
  contenido) y borra el stack del pipeline. La conexión a GitHub se borra a mano.

## Guion de la demo

1. **Preparación, el día anterior:** subir el repo a GitHub, crear la conexión en la consola,
   desplegar `pipeline.yaml` y anotar la `ApiUrl`.
2. **Despliegue normal:** `VERSION = "2"`, hacer push y correr `trafico.sh` cuando el pipeline llegue
   a Deploy. Se ven v1 y v2 mezcladas y, a los ~5 min, solo v2.
3. **Rollback:** `FALLAR = True` y push. Los tests pasan, el 10 % del tráfico recibe errores,
   la alarma salta y todo vuelve solo a la versión anterior.

## Cosas que conviene saber antes de presentar

- **El pipeline termina en rojo después del rollback.** Es lo esperado, porque falla la etapa Deploy.
  Conviene decirlo para que el público no piense que algo salió mal.
- **Después del rollback, `FALLAR = True` sigue en el repo.** Hay que volver a ponerlo en `False`
  y hacer push antes de otra corrida o del ensayo siguiente.
- **Cómo se ve el error.** Cuando la Lambda lanza una excepción, API Gateway responde **HTTP 502**
  con `{"message": "Internal server error"}`. En `trafico.sh` se ve como `[HTTP 502]`.
- **`trafico.sh` tiene `set -e`.** Si un `curl` falla por red, por ejemplo un corte de wifi,
  el script se detiene y hay que volver a lanzarlo. Los HTTP 500/502 no lo cortan.
- **Los log groups no se borran.** `limpiar.sh` no borra los de CloudWatch que crean Lambda y
  CodeBuild. Cuestan casi nada, pero quedan.
- **AWS Academy puede bloquear la demo.** Si usás AWS Academy, es probable que no deje crear roles IAM
  y el despliegue de `pipeline.yaml` falle. Vale la pena probarlo con tiempo.
