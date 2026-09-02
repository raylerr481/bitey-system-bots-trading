# Bitey System Bots Trading — Technical Audit

**Fecha:** 2026-09-02  
**Repositorio:** `raylerr481/bitey-system-bots-trading`  
**Rama auditada:** `main`  
**Objetivo:** pasar de auditoría conceptual a verificación técnica del núcleo SBT, manteniendo demo/paper separados de dinero real.

## 1. Resultado ejecutivo

**Estado:** arquitectura de seguridad bien encaminada, pero todavía no debe considerarse lista para trading real.

**Decisión de esta etapa:** continuar con demo/paper, pruebas automatizadas y endurecimiento del flujo de autorización antes de cualquier habilitación live.

## 2. Evidencia inspeccionada

### `app/main.py`
- FastAPI declara versión `0.7.0`.
- Modos declarados: `demo`, `paper`, `live`.
- La API rechaza explícitamente `live` en `/api/v1/config/validate`.
- El endpoint de sistema declara `live_trading_enabled: false` y modos operativos `demo`/`paper`.
- Existe catálogo de proveedores IA, transportes y política de coste.

### `app/mcp/server.py`
- MCP está montado bajo `/mcp`.
- Existe `BearerGate` y el servicio falla cerrado si `SBT_MCP_TOKEN` no está configurado.
- Las herramientas MCP exponen estado, plataformas, permisos, plan de conexión y Risk Gate.
- `mt5_status` y `mt5_quote` están definidos como lectura; no existe una herramienta MCP de colocación de órdenes MT5.
- El estado MCP declara `broker_credentials_exposed_to_ai: false`.

### `app/api/integrations.py`
- Registry explícito para MT5, TradingView y Alpaca.
- Permisos separados por nivel de riesgo: lectura, research, escritura de estrategia, demo, paper y live.
- `live` y `live_execute` son rechazados en el plan de conexión.
- La automatización exige permiso explícito de ejecución demo/paper.

### `app/intelligence/provider_guard.py`
- Política fail-closed para proveedores externos.
- Requiere consentimiento del usuario y propietario de facturación `user` para llamadas externas API pagadas.
- El fallback automático queda bloqueado cuando `exclusive=true`.
- `DIRECT_USER` evita que SBT consuma directamente la cuota API externa.

### `app/risk/engine.py`
- Existe `RiskEngine` determinista.
- Límite de posición por porcentaje de capital.
- Límite de pérdida diaria.
- Las decisiones son explícitamente `allowed/reason`.

### `app/services/demo_engine.py`
- Las órdenes demo pasan por `RiskEngine` antes de simularse.
- El motor modifica únicamente capital virtual.
- La compra comprueba efectivo virtual suficiente.

### `app/api/demo.py`
- Portfolio demo inicial de R$10.000/unidades de capital ficticio.
- Endpoint de estado declara `real_money: false` y `broker_orders: false`.

## 3. Hallazgos

### P0 — No habilitar live todavía
Aunque existen nombres y permisos para `live`, el código actual mantiene la ejecución real bloqueada. Esto es correcto para el hito actual. **No convertir esta bandera en true como siguiente paso.**

### P1 — Riesgo: ejecución demo demasiado accesible por API
`POST /api/v1/trading/demo/order` construye y simula una orden directamente. En el archivo inspeccionado no aparece autenticación de usuario ni un permiso por usuario alrededor de este endpoint. Para una aplicación multiusuario, debe colocarse detrás de autorización y límites por sesión/usuario.

### P1 — Riesgo: parámetros de orden
`side` se recibe como `str` y el `DemoEngine` compara contra `Side.BUY`; conviene validar el enum `Side` en el request para rechazar valores inválidos antes de llegar al motor.

### P1 — Risk Engine necesita ampliar cobertura
El motor actual controla tamaño de posición y pérdida diaria, pero todavía no evidencia controles de símbolo permitido, cantidad máxima, exposición agregada, stop-loss obligatorio, slippage, spread, cooldown, número de operaciones, ni emergency-stop persistente.

### P1 — Auditoría operacional
Los archivos inspeccionados no evidencian todavía un audit trail persistente para cada decisión IA → herramienta → Risk Gate → ejecución demo/paper. Debe existir antes de cualquier eventual etapa live.

### P2 — Consistencia de estado demo
`app/api/demo.py` mantiene un portfolio global en memoria y `app/api/trading.py` crea otro portfolio global. Esto puede producir estados demo diferentes según endpoint y no representa correctamente sesiones/usuarios. Debe consolidarse en un servicio de portfolio con identidad de cuenta/simulación.

### P2 — Pruebas
En esta revisión de archivos no se ejecutaron tests del repositorio. Por tanto, **no se declara que el comportamiento haya sido probado en runtime**. El siguiente hito debe incorporar pruebas unitarias e integración para MCP, permisos, provider guard, Risk Engine y demo engine.

## 4. Arquitectura objetivo para el siguiente hito

```text
Usuario
  ↓
Web / App
  ↓
Autenticación + Tenant/User Context
  ↓
AI Provider Registry
  ↓
MCP / API / SDK / Webhook Connector
  ↓
Permission Resolver
  ↓
Strategy Validation
  ↓
Risk Gate
  ↓
Execution Adapter
  ↓
Demo / Paper
  ↓
Audit Trail + Portfolio
```

La IA puede proponer análisis, estrategia o una llamada a herramienta. **La IA no obtiene autoridad directa para ejecutar.** SBT valida identidad, permisos, parámetros y riesgo antes de cualquier operación.

## 5. Próximas acciones priorizadas

1. Crear `ExecutionAuthorization` asociado a usuario/sesión.
2. Proteger `demo/order` y `paper` con permisos explícitos.
3. Cambiar `side: str` a enum validado.
4. Centralizar Portfolio/Demo Account por usuario.
5. Crear `AuditEvent` para cada decisión y ejecución.
6. Ampliar Risk Engine con exposición, stop-loss, límites por instrumento y emergency stop.
7. Añadir suite de tests y CI.
8. Verificar MCP con token real de entorno sin registrar secretos.
9. Conectar Market Intelligence al flujo de análisis sin conceder autoridad de ejecución.
10. Mantener `live` bloqueado hasta completar una revisión de seguridad independiente y pruebas de extremo a extremo.

## 6. Criterio de avance

El siguiente avance técnico debe demostrar con evidencia que una petición IA puede recorrer:

**selección IA → selección plataforma → permisos → estrategia → Risk Gate → demo/paper → auditoría**, con rechazo determinista cuando falta autorización.

**Estado live al cierre de esta auditoría: BLOQUEADO.**

---

_Auditoría técnica registrada en GitHub el 2026-09-02 como evidencia de evolución del proyecto._
