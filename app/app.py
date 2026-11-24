import json

# Para la demo: cambiar VERSION y hacer git push dispara todo el pipeline.
VERSION = "2"

# Para la demo de rollback: poner en True y hacer push.
# Simula un bug que los tests NO detectan (solo falla con un "context" real de
# Lambda), asi que llega al canario y la alarma de CloudWatch lo revierte.
FALLAR = False


def lambda_handler(event, context):
    if FALLAR and context is not None:
        raise RuntimeError("Fallo intencional para demostrar el rollback")

    return {
        "statusCode": 200,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(
            {
                "mensaje": f"Hola desde AWS, versión {VERSION}",
                "version": VERSION,
            },
            ensure_ascii=False,
        ),
    }
