# Proceso de compra

Proceso BPMN leído de Enterprise Architect (paquete `Model/Proceso de compra`) con ea-steroids.

## Participantes

| Participante (pool) | Responsables (carriles) |
|---|---|
| Empresa | Solicitante, Jefe de área |
| Proveedor | — (externo) |

## Recorrido

| N° | Responsable | Paso | Tipo | Sigue |
|---|---|---|---|---|
| 1 | Solicitante | Necesidad de compra | Inicio | 2. Registrar solicitud |
| 2 | Solicitante | Registrar solicitud | Tarea de usuario | 3. Revisar solicitud |
| 3 | Jefe de área | Revisar solicitud | Tarea de usuario | 4. ¿Aprobada? |
| 4 | Jefe de área | ¿Aprobada? | Compuerta exclusiva | 5. Emitir orden de compra [Sí: aprobada == true]<br>6. Notificar rechazo [No: aprobada == false] |
| 5 | Jefe de área | Emitir orden de compra | Tarea de servicio | 7. Esperar confirmación (2 días) |
| 6 | Solicitante | Notificar rechazo | Tarea de envío | 8. Solicitud rechazada |
| 7 | Jefe de área | Esperar confirmación (2 días) | Evento intermedio (temporizador) | 9. Compra aprobada |
| 8 | Solicitante | Solicitud rechazada | Fin | — |
| 9 | Jefe de área | Compra aprobada | Fin | — |

## Decisiones

**4. ¿Aprobada?** (Compuerta exclusiva)

- **Sí** → Emitir orden de compra — condición: `aprobada == true`
- **No** → Notificar rechazo — condición: `aprobada == false`

## Mensajes con otros participantes

- Emitir orden de compra → **Proveedor**: Orden de compra

## Diagrama

```mermaid
flowchart LR
    subgraph g1["Solicitante"]
        n5(("Necesidad de compra"))
        n6["Registrar solicitud"]
        n10["Notificar rechazo"]
        n12(("Solicitud rechazada"))
    end
    subgraph g2["Jefe de área"]
        n7["Revisar solicitud"]
        n8{"¿Aprobada?"}
        n9["Emitir orden de compra"]
        n14(("Esperar confirmación (2 días)"))
        n11(("Compra aprobada"))
    end
    p_2[["Proveedor"]]
    n5 --> n6
    n6 --> n7
    n7 --> n8
    n8 -->|"No: aprobada == false"| n10
    n8 -->|"Sí: aprobada == true"| n9
    n9 --> n14
    n10 --> n12
    n14 --> n11
    n9 -.->|"Orden de compra"| p_2
```
