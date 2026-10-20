# API de actividades de Dynamic Notch (v1)

Cualquier script, Atajo o app de tu Mac puede poner **su propia actividad** en la Isla Dinámica: una compilación, una descarga, los tests, un render, un deploy. Funciona como las Live Activities del iPhone. Inicias la actividad, la actualizas con lo que cambia y la terminas. Al terminar muestra un resumen unos segundos y se va.

Hay tres formas de usarla. Las tres aplican el mismo contrato:

| Forma | Para qué |
|---|---|
| Comando `dynamicnotch` | Terminal, scripts y builds |
| HTTP `POST 127.0.0.1:48123/activity` | Cualquier lenguaje |
| URL `dynamicnotch://activity?…` | Atajos ("Abrir URL"), Raycast, Alfred |

Solo se escucha en tu propia Mac (127.0.0.1). Las conexiones de otras máquinas se rechazan.

## Instalar el comando

Desde la carpeta del proyecto (si `/usr/local/bin` pide permiso, usa `~/bin` u otra carpeta de tu `PATH`):

```bash
ln -sf "$PWD/scripts/dynamicnotch" /usr/local/bin/dynamicnotch
```

## Ejemplos rápidos

```bash
# Compilación con progreso
dynamicnotch start build --title "Compilando" --icon hammer.fill --progress 0
dynamicnotch update build --progress 0.6 --value "6/10"
dynamicnotch end build --title "Listo" --color green --after 4

# Ejecutar cualquier comando con su actividad: ✓ verde si sale bien, ✗ roja (y se expande) si falla.
# Devuelve el código de salida del comando, así que sirve dentro de otros scripts.
dynamicnotch run tests --title "Tests" --icon checklist -- swift test
dynamicnotch run deploy --title "Deploy" --icon icloud.and.arrow.up -- ./deploy.sh

# Algo que pide atención: se expande un momento y suena
dynamicnotch update deploy --title "Esperando aprobación" --color orange --alert --sound
```

Desde Atajos usa la acción **Abrir URL**:

```
dynamicnotch://activity?id=cafe&title=Café%20listo&icon=cup.and.saucer.fill&color=orange&alert
```

Por HTTP:

```bash
curl -X POST 127.0.0.1:48123/activity \
  -H 'Content-Type: application/json' \
  -d '{"id":"render","title":"Renderizando","icon":"film","progress":0.25,"url":"https://example.com/render/42"}'
```

## Contrato

`POST /activity` con un objeto JSON de **4 KB como máximo**, como el límite del iPhone.

| Campo | Tipo | Notas |
|---|---|---|
| `id` | texto, **requerido** | Letras, números, `.`, `-` y `_` (1–64). Identifica tu actividad. |
| `action` | `start` · `update` · `end` | Opcional: si el `id` ya existe es `update`; si no, `start`. |
| `title` | texto (80) | Lo principal. |
| `subtitle` | texto (160) | Se ve en la tarjeta expandida. |
| `icon` | símbolo SF | Por ejemplo `hammer.fill` o `arrow.down.circle`. Si no existe se usa `app.badge.fill`. |
| `color` | `#RRGGBB` o nombre | `green`, `blue`, `red`, `orange`, `yellow`, `purple`, `pink`, `teal`, `indigo` o `gray`. |
| `progress` | 0…1 | Anillo en la bolita y barra en la tarjeta expandida. |
| `value` | texto (12) | Texto corto a la derecha, como `3/10` o `2:41`. Con `progress` y sin `value` se muestra el porcentaje. |
| `url` | http/https | Se abre al hacer clic. En la tarjeta expandida sale el botón "Abrir". |
| `relevance` | 0…1000 | Orden frente a otras actividades. Por defecto vale 700 (la música vale 500 y una llamada 920). |
| `placement` | `bubble` · `notch` | Por defecto `bubble`: vive como bolita y no le quita el lugar a la música. Con `notch` puede ocupar el notch si es la más relevante. |
| `staleAfter` | segundos | Si no la actualizas en ese tiempo se ve atenuada, como "sin actualizar". |
| `alert` | `true` o `{"sound": true}` | Con esta actualización se expande unos segundos. Hay como máximo una alerta cada 30 s, y nunca mientras usas el notch. |
| `dismissAfter` | segundos (0–60) | Solo con `end`: cuánto se queda el resumen. Por defecto usa el ajuste "Resumen al terminar". |

Las actualizaciones solo necesitan los campos que cambian. Los demás se conservan.

### Respuestas

| Código | Cuándo |
|---|---|
| `200` | `{"status": "started" \| "updated" \| "ended", "id": "…", "version": 1}` |
| `400` | JSON inválido, `id` inválido o un campo fuera de rango (`error` dice cuál) |
| `404` | `update` o `end` de un `id` que no existe |
| `429` | Ya hay 4 actividades de la API a la vez |

`GET /activity` lista las actividades de la API vivas.

## Reglas (como en el iPhone)

- Hasta **4** actividades de la API a la vez.
- Una actividad vive como máximo **8 horas**; después se termina sola.
- Las alertas son para lo esencial, así que no hay que mandar `alert` en cada actualización.
- El texto se recorta a los largos de la tabla para que siempre quepa en la isla.

## Más ejemplos

**Xcode: fase "Run Script" de un build**

```bash
dynamicnotch start xcode --title "Build $PRODUCT_NAME" --icon hammer.fill --value "$CONFIGURATION"
```

Y en un "Post-action" del esquema: `dynamicnotch end xcode --title "Build listo" --color green`.

**Descarga con progreso (curl)**

```bash
dynamicnotch start dl --title "Descargando" --icon arrow.down.circle --progress 0
curl -L -o archivo.zip "$URL" --progress-bar 2>&1 | tr '\r' '\n' | while read -r line; do
  pct=$(printf '%s' "$line" | grep -oE '[0-9]+(\.[0-9])?%' | tail -1 | tr -d '%')
  [ -n "$pct" ] && dynamicnotch update dl --progress "$(echo "scale=3; $pct/100" | bc)"
done
dynamicnotch end dl --title "Descarga lista" --color green
```

**Esperar un trabajo en la nube** (por ejemplo, un workflow de GitHub Actions con `gh`)

```bash
dynamicnotch start ci --title "CI" --icon arrow.triangle.2.circlepath --stale 120
gh run watch "$RUN_ID" --exit-status && dynamicnotch end ci --title "CI verde" --color green \
  || dynamicnotch end ci --title "CI falló" --color red --alert
```

Las Actions corren en servidores de GitHub y no pueden llegar a tu Mac. Por eso el ejemplo vigila la ejecución desde tu Mac con `gh run watch`.
