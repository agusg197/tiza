# Tiza

*De la tiza al markdown.* Foto de un pizarrón o de una hoja escrita a mano → markdown
estructurado, con el OCR corriendo en el dispositivo y una sola llamada al modelo.

| papel | pizarrón |
|---|---|
| <img src="capturas/vacio-papel.png" width="330" alt="Estado vacío en modo claro"> | <img src="capturas/resultado-pizarron.png" width="330" alt="Resultado en modo oscuro"> |

**Español** · [English](README.en.md)

## Lo que este repo tiene para mostrar

No es la app: son las mediciones, y sobre todo **lo que midieron**.

Construí tres formatos de serialización del layout, structured output contra un schema, y
un algoritmo de detección de columnas. Después armé la eval, y dijo esto:

- **La configuración más barata también era la mejor.** `plain` + markdown libre saca 100%
  en todo, al 43% del costo de la más cara que también acierta.
- **El algoritmo de columnas tiene cero ganancia medible.** Fue la parte que más trabajo
  llevó —XY-cut, umbral, ocho tests de layout— y el modelo resultó ser indiferente al orden
  cuando tiene las coordenadas: dos serializaciones con órdenes radicalmente distintos dan
  resultados idénticos, token por token.
- **Las coordenadas no son una mejora de calidad, son el precio del structured output.**
  Sin ellas el schema inventa action items; con markdown libre no hacen falta.

Los números están abajo en *Resultados*, con las **dos** corridas: la primera, sobre un caso
fácil, decía lo contrario. La reversión entre las dos es el hallazgo, así que quedan las dos.

También quedaron escritos los errores del camino: un model id copiado de la documentación
sin probarlo que devolvía 404, una métrica propia con un punto ciego que encontré mirando la
salida y no la tabla, y un umbral que **no** afiné porque hacerlo con cinco casos habría sido
overfitting.

El objetivo del proyecto era practicar **el patrón híbrido**: hacer el trabajo barato en el
dispositivo y gastar tokens sólo donde el modelo agrega valor. Todo lo demás —cuentas,
historial, backend, multi-idioma— quedó explícitamente afuera.

## Estado

Fase 1, pasos 1 a 6 cerrados. El 7 tiene el harness armado y le falta el golden set.

| Paso | Estado |
|---|---|
| 1. Esqueleto: una pantalla, cámara/galería, preview | listo |
| 2. OCR crudo con MLKit + latencia y confianza en pantalla | listo |
| 3. Serialización con layout, formatos intercambiables | listo |
| 4. Primera llamada al LLM (Gemini Flash), sin schema | listo |
| 5. Structured output con schema, parseo estricto y render | listo |
| 6. Los estados de error, cada uno con su salida | listo |
| 7. Runner de evals, métricas y export de fixtures | listo |
| 7b. Cinco casos de layout sintéticos, con las cajas reales de MLKit | listo |
| 7c. El golden set: 15-20 fotos reales con su markdown | **pendiente** |

## Arquitectura

```
Foto (image_picker)
 └─> MlkitOcrService              [on-device, gratis]
      └─> OcrResult               (Dart puro: blocks → lines + boundingBox + confidence)
           └─> LayoutSerializer   (intercambiable)
                └─> LlmClient     (intercambiable)  [caro, y sólo si el usuario lo pide]
                     └─> StructuredNote  (validada contra el schema)
                          └─> renderNoteMarkdown()   → markdown
                          └─> StructuredNoteView     → widgets
```

La llamada al modelo es una acción explícita del usuario, no un paso automático del
pipeline. Hasta que se toca "Estructurar", nada salió del teléfono.

Dos decisiones que importan más de lo que parecen:

**`OcrResult` no arrastra tipos nativos.** [`lib/ocr/mlkit_ocr_service.dart`](lib/ocr/mlkit_ocr_service.dart)
es el único archivo que conoce MLKit; de ahí para adelante todo es Dart puro. Por eso los
tests de la serialización corren con `flutter test` en la máquina, sin emulador, y por eso
`OcrResult.toJson()` alcanza para congelar el OCR de una foto como fixture. El runner de
evals lee esos fixtures en vez de re-correr MLKit, y por eso las evals corren en
milisegundos, sin dispositivo y con resultados idénticos entre corridas.

**`LayoutSerializer` es una interfaz, no una función.** El formato de serialización es
*la* variable que se va a mover en las evals. Comparar dos formatos tiene que ser un
cambio de valor, no un cambio de código.

## Los tres serializadores

`plain` — los bloques en el orden de lectura de MLKit, sin posiciones. Línea de base.

`coords` — una línea por renglón, con `[y x alto]` normalizados a 0–100:

```
# formato: [y x alto] texto
[  5   8 100] Sprint planning
[ 15  54  52] Action items
[ 15   9  62] Objetivos
```

El alto es **relativo al texto más grande de la foto**, no al alto de la imagen.
Normalizado contra la imagen un título y un bullet caen en 4 y 2, dos valores
indistinguibles; relativo al máximo quedan en 100 y 42.

`columns` — el mismo formato, pero ordenando por bloques de layout con **XY-cut** en
vez de por `y`. Existe para arreglar el hallazgo del paso 3, y abajo está la medición
de si lo arregla.

XY-cut es el algoritmo clásico de segmentación de página: se busca el hueco de blanco
más ancho, se corta ahí, y se repite en cada mitad. Dos cosas propias:

**El eje del corte no está fijado de antemano**: en cada nivel gana el hueco más grande
medido en proporción a la imagen. En la foto de prueba el hueco entre columnas (15% del
ancho) le gana al hueco bajo el título (5,6% del alto), así que corta primero en
columnas y cada una sale entera. Cortando siempre en horizontal primero el orden también
queda con los bloques contiguos, pero manda "Riesgos" después de la columna derecha
—una secuencia distinta de la que uno leería—, y eso **la métrica de orden no lo
penaliza**, porque cuenta contigüidad y no secuencia. Es un límite de la métrica, no una
virtud del eje adaptativo: la razón para elegirlo es que generaliza mejor, no que este
caso lo demuestre.

**Una canaleta tiene que medir al menos 4 alturas de texto**, además del 4% del ancho.
Esta condición salió de un bug concreto y está cubierta por un test: un encabezado corto
con sus bullets corridos a la derecha deja un hueco que pasa el 4%, y el algoritmo lo
cortaba como si fueran dos columnas. Con una sola sección el orden salía bien de
casualidad —el encabezado cae a la izquierda de sus bullets—, pero con dos secciones los
encabezados se iban todos adelante:

```
Objetivos, Riesgos, primero, segundo, tercero   ← lo que salía
Objetivos, primero, segundo, Riesgos, tercero   ← lo correcto
```

La distancia absoluta no distingue una sangría de una canaleta; la distancia medida en
alturas de texto sí. Una sangría son dos o tres, una canaleta son varias más.

## La llamada al modelo

**La key la pone el usuario** (BYOK), guardada con `flutter_secure_storage` —Keystore de
Android, RSA OAEP + AES-GCM—. No es un atajo: una key compilada dentro del APK se puede
extraer del binario, así que embebida no protegería nada, y de paso cada usuario usa su
propio tier gratuito. Consecuencia práctica linda: el proyecto se compila y se recorre
completo sin ninguna key.

<img src="capturas/ajustes-byok.png" width="330" alt="Ajustes: campo para la key y selector de modelo">

La pantalla dice de dónde se saca la key y **también la letra chica**: en el tier gratuito
Google usa el contenido para mejorar sus productos. Acá no sale la foto, sale el texto del
OCR — que es justamente la parte sensible. Esconder eso habría sido más cómodo.

**`LlmClient` es una interfaz**, con [`GeminiClient`](lib/llm/gemini_client.dart) que sale
a la red y [`FakeLlmClient`](lib/llm/fake_llm_client.dart) que devuelve una respuesta fija.
El fake no es decoración para los tests: permite recorrer la app entera sin key, y aparece
etiquetado como simulado en el panel del modelo — mostrar un resultado inventado sin
decirlo sería justo el problema que este proyecto trata de medir.

**El modelo se elige en los ajustes**, entre los Flash y Flash-Lite que entran en el tier
gratuito. `ModelOption` separa el `id` estable —el que va a la tabla de resultados— del
`apiId` que espera Google, así que si Google renombra un modelo la preferencia del usuario
y el histórico de evals sobreviven.

Con eso quedan **tres ejes** para el paso 7 — tres formatos de serialización, tres modelos y
dos modos de salida (con schema o markdown libre) — y la tabla de resultados pasa de ser una
columna a ser una matriz de 18 combinaciones. Los tres se cambian desde la app, sin tocar
código.

Cuatro decisiones que se pueden discutir, y por eso están anotadas en el código:

- **La key va en el header `x-goog-api-key`, no en `?key=`.** La doc oficial muestra el
  query param, pero ahí la key termina en logs de acceso, historiales y cualquier proxy
  del camino.
- **Las reglas van en `systemInstruction`, separadas del texto del OCR.** Si viajaran en el
  mismo bloque, un renglón del pizarrón que se lea como una instrucción podría competir con
  ellas. La nota es un dato, no una orden. Hay un test que verifica esa separación.
- **`temperature: 0`.** Sin esto, correr el golden set dos veces da resultados distintos y
  las evals no comparan nada.
- **Las respuestas se cachean por (serializador, modelo).** La app existe para comparar
  formatos, así que ir y volver entre los dos es el gesto más frecuente que hay; sin caché
  cada vuelta paga tokens de nuevo por una entrada idéntica.

En el camino de markdown libre la respuesta se muestra **sin renderizar**, a propósito. El
paso 4 existe para ver qué devuelve el modelo antes de restringirlo, y renderizarlo esconde
justo lo que se está mirando: un encabezado de nivel equivocado, un bullet suelto, un bloque
de código que no se pidió. Lo único que se toca es marcar la sintaxis en terracota.

## El schema y la validación estricta

El cambio central del paso 5 es este: **el markdown deja de escribirlo el modelo**. La API
devuelve datos contra un [`responseSchema`](lib/llm/note_schema.dart), se validan, y el
markdown lo produce `renderNoteMarkdown`, una función pura. El formato pasa de depender de
que el modelo obedezca a ser determinista.

Eso tiene un efecto secundario que no esperaba: **el prompt se acortó**. Con el schema
puesto, todas las instrucciones de formato —"respondé sólo markdown", "no lo envuelvas en un
bloque de código"— dejan de hacer falta, porque las impone la API. Quedan sólo reglas de
contenido, que ningún schema puede imponer: no inventar, no corregir el OCR, no poner el
mismo renglón en dos lados. Hay un test que verifica que el prompt con schema no volvió a
mencionar formato.

El schema es **chato a propósito**: dos niveles y nada más. La especificación lo pide en esas
palabras, y `depth` es la concesión — permite expresar jerarquía sin anidar la estructura, así
que el error posible es un número mal elegido en vez de un árbol mal armado. Hay un test que
falla si el anidamiento crece.

Dos detalles de la API que cuestan un 400 si se ignoran, y que están cubiertos por tests:

- Los tipos van en **mayúsculas** (`STRING`, `OBJECT`, `ARRAY`, `INTEGER`). Es un enum de
  proto, no JSON Schema estándar. Un test recorre el schema entero y falla si aparece uno en
  minúsculas.
- `propertyOrdering` es una extensión de Google y no es cosmética: el modelo genera en ese
  orden. En `actionItems` va `text` antes que `owner` porque decidir el responsable antes de
  haber escrito la tarea lo empuja a inventar dueños.

### La decisión que importa: descartar y contar

Ante una entrada inválida, [`parseStructuredNote`](lib/llm/structured_note.dart) **descarta
esa entrada y sigue**, y anota qué descartó. Las tres alternativas eran peores:

- Tirar toda la respuesta por un bullet vacío desperdicia una llamada que salió bien en un 95%.
- Aceptarla en silencio hace que las evals midan de más.
- Reintentar automáticamente arregla la pantalla y **esconde la tasa de fallo**, que es justo
  el número que este proyecto quiere medir. El usuario tiene el botón para volver a preguntar.

Un caso vale la pena: una sección que viene sin encabezado pero con bullets no se descarta,
se conserva sin título. Tirarla perdería texto que el OCR sí leyó bien.

El JSON malformado sí es fatal — ahí no hay nada que recuperar.

La cuenta de descartes aparece en el panel del modelo y el detalle arriba de la nota, porque
un modelo que acierta el contenido pero devuelve tres entradas inválidas por foto no es
equivalente a uno que devuelve cero. Esa cuenta es una columna de la tabla de resultados.

<img src="capturas/vista-json.png" width="330" alt="Vista JSON con la respuesta cruda del modelo">

La vista JSON al lado de la estructura contesta una pregunta distinta: si la nota salió mal,
¿se equivocó el modelo o entendió mal el schema? Esta captura es de una respuesta real, y no
tiene descartes — el modelo cumplió el schema. El panel de validación aparece cuando no lo
cumple, y el caso simulado lo trae a propósito para poder verlo.

### El render

La nota se dibuja con widgets nativos, sin ningún paquete de markdown. No es sólo que
`flutter_markdown` esté discontinuado: **no haría falta ni existiendo**, porque después del
schema llegan datos tipados y no texto que haya que interpretar. Ese es el beneficio concreto
de haber impuesto la estructura, más allá de la calidad de la salida.

El visor de la respuesta tiene dos vistas, ESTRUCTURA y JSON, porque contestan preguntas
distintas: la primera dice si la nota quedó bien, la segunda si el modelo entendió el schema.
Con sólo la primera, un error de campos se confunde con un error de contenido.

### Qué está verificado y qué no

El parseo de la respuesta y el mapeo de errores tienen tests con JSON de ejemplo: tokens,
`finishReason`, bloqueo por filtros de contenido, 200 con cero texto por límite de tokens,
cuerpo que no es JSON, y los códigos 400/401/403/429/5xx. El paso 5 agrega el schema (tipos
en mayúsculas, `required` consistente, anidamiento acotado), cada rama del parseo estricto y
el markdown renderizado carácter a carácter.

La forma del request está verificada contra la **API real**, con una key deliberadamente
inválida:

```
HTTP 400 · API_KEY_INVALID · "API key not valid. Please pass a valid API key."
```

Eso confirma tres cosas que un test con mocks no puede: que la URL y el model id son
correctos (un path mal armado daría 404), que Google **lee** el header —evaluó la key y la
rechazó, en vez de decir que faltaba— y que ese 400 cae en la rama `invalidKey` del mapeo.

El camino de éxito también está verificado, con una key real:

<img src="capturas/llamada-real.png" width="330" alt="Llamada real: panel on-device arriba, panel del modelo abajo">

Los dos paneles separados son a propósito: arriba lo que salió gratis en el teléfono, abajo
lo que costó tokens. Toda la tesis del proyecto en una pantalla.

| | |
|---|---|
| modelo | `gemini-3.5-flash-lite` |
| serializador | `columns` |
| tokens | 411 → 120 |
| latencia | 1350 ms |
| entradas descartadas | 0 |

### El model id que estaba mal, y por qué

La primera llamada real no devolvió 200 sino **404**:

```
This model models/gemini-2.5-flash is no longer available to new users.
```

La familia 2.5 —la que sugería la especificación del proyecto— está retirada para keys
nuevas. Lo mismo con `gemini-2.5-flash-lite`, probado aparte. Los dos salieron del selector:
una opción que falla siempre no es una opción.

De dónde vino el error importa más que el error: los ids los tomé de un resumen de la
documentación, sin probarlos. Ese mismo resumen ya me había dado mal la forma del request, así
que la señal estaba ahí. **Un id de modelo no se verifica leyendo docs, se verifica haciendo
la llamada.**

Y el 404 llegó legible sólo por el "ver el detalle" del paso 6: sin él era un `404` mudo.

## Evals

El harness está armado y verificado; lo que falta son las fotos.

**Los fixtures guardan el OCR, no la imagen.** Es la decisión que sostiene todo lo demás: las
evals corren en la máquina en milisegundos, sin emulador y sin MLKit, y dos corridas de la
misma configuración dan exactamente lo mismo. Es también la razón por la que `OcrResult` no
arrastra tipos nativos desde el paso 1 — esto era el plan desde ahí. La imagen se guarda al
lado sólo para poder mirarla cuando un número no cierra.

```
fixtures/<caso>/
  ocr.json          OcrResult.toJson(), congelado
  expected.md       el markdown que debería salir, escrito a mano
  foto.png          para mirar cuando algo no cierra
  serializado.txt   lo que vio el modelo, para leerlo sin correr nada
```

**El runner es un script, no un test.** Gasta tokens contra una API real, y algo que cuesta
dinero no tiene que poder dispararse por correr `flutter test`. Lo que puede tener bugs —las
métricas y los dos parsers— sí está en tests.

```bash
dart run tool/evals.dart --dry-run
```

```bash
dart run tool/evals.dart --serializers plain,coords --models flash-lite-3.5,flash-3.5 --modes schema,freeMarkdown
```

Los tres ejes se mueven por flag y el script imprime cuántas llamadas va a hacer antes de
empezar. `--fake` corre el pipeline completo con la respuesta simulada: cero tokens, sin key, y
sirve para verificar que la cañería está conectada sin medir nada del modelo.

### La métrica que no cuesta nada

Antes de la tabla que gasta tokens, el runner imprime otra que **no llama al modelo**.
Sobre los cinco casos de layout de `fixtures/`:

```
| serializador | casos | saltos | ideal | de más | inversiones | perfectos |
|---|---|---|---|---|---|---|
| plain        | 5     | 16     | 12    | 4      | 2           | 3/5       |
| coords       | 5     | 26     | 12    | 14     | 26          | 1/5       |
| columns      | 5     | 14     | 12    | 2      | 2           | 3/5       |
```

Un serializador que recorre cada bloque de punta a punta antes de pasar al siguiente hace
exactamente `bloques - 1` **saltos**. Cada salto de más es una vez que intercaló contenido
de dos bloques. Las **inversiones** cuentan aparte los bloques que llegaron enteros pero
cambiados de lugar.

Esa segunda columna se agregó porque la primera tenía un punto ciego real: `columns` sacaba
cero saltos de más en el caso de dos columnas y aun así entregaba la columna derecha antes
del bloque de abajo de la izquierda. Contigüidad no es secuencia, y la métrica lo estaba
dando por perfecto. Lo encontré mirando la salida de `--show`, no la tabla — de ahí que ese
flag exista.

Lo que dicen los números:

- **`coords` es decisivamente el peor**: 14 saltos de más y 26 inversiones, falla 4 de 5.
  Ordenar por `y` es lo que la especificación proponía y la medición lo descarta.
- **`columns` y `plain` empatan en casos perfectos pero fallan en casos distintos y
  complementarios**, y `columns` hace la mitad de saltos de más.
- Y un dato sobre MLKit: **su propio orden de bloques también parte las secciones
  indentadas**. En `001` devuelve `Notas, Objetivos, Riesgos, cerrar…` — los dos
  encabezados juntos y después todos los bullets. Es exactamente el bug que tenía mi
  XY-cut antes de la condición de las alturas de texto.

Esto es lo mejor del harness: iterar sobre el layout sale gratis y es determinista. Por eso
`LayoutSerializer` expone `order()` aparte de `serialize()`, y por eso el runner lista **qué
caso** falla en cada serializador — dos saltos de más pueden ser un límite conocido o un bug
nuevo, y sin el desglose no se distinguen.

### El umbral que no se puede afinar todavía

La condición de "canaleta ≥ 4 alturas de texto" tiene un valor que **no está ajustado, y no
se puede ajustar con los datos que hay**. Medido:

| multiplicador | secciones indentadas | dos columnas |
|---|---|---|
| 4 o 3 | bien | 1 inversión |
| 2 | **se rompe** | bien |

Los dos casos se contradicen porque el hueco de sangría depende del largo del encabezado
—que es contenido, no layout—. Probé dos señales alternativas para desempatar: exigir que
los dos lados tengan más de un renglón, y que sus rangos de `y` se solapen. Ninguna separa
los casos.

Quedó en 4, que es el valor que sale del razonamiento y no de ajustar contra cinco
imágenes. Bajarlo a 2 daría 4/5 en vez de 3/5 en esta tabla, y sería **overfitting sobre
cinco casos sintéticos**: la tabla mejora y no hay ninguna razón para creer que el
algoritmo mejoró. Se decide con fotos reales.

Y como un número que mejora sin poder mirar qué cambió es un número en el que no se puede
confiar, `--show` imprime la serialización cruda de cada caso.

### Las decisiones de las métricas

La especificación es explícita en que **no se busca exactitud carácter por carácter**. Lo que
se mide es si el contenido terminó en el lugar correcto, y eso obliga a cuatro decisiones:

- **La comparación saca los acentos.** El OCR pierde tildes —en la foto de prueba devolvió
  "metricas"— y el prompt le prohíbe al modelo corregir lo que leyó el OCR. Si la comparación
  fuera sensible a la tilde, marcaría un fallo de estructuración donde hubo uno de OCR. Son
  cosas distintas y se miden por separado: la calidad del OCR ya la mide la confianza de MLKit.
- **Los bullets se comparan aplanados**, sin exigir que cayeran en la misma sección. Penalizar
  dos veces el mismo error —una por el bullet y otra por la sección— haría que los números no
  se puedan leer.
- **El responsable se cuenta aparte.** Un action item bien detectado con el dueño equivocado es
  un error distinto, y menos grave, que no detectarlo.
- **El modo sin schema se lee con el mismo parser que el golden set.** Uno más permisivo para
  la respuesta que para lo esperado le daría al markdown libre una ventaja artificial.

Además: los casos incompletos se saltean **y se reportan**. Un golden set que dice tener 20
casos y corre 14 en silencio produce números que no significan nada.

### Cómo armar el golden set

En la pestaña "lo que ve el modelo" hay un **GUARDAR COMO FIXTURE**. Guarda el OCR de esa foto
en el almacenamiento externo de la app, con un `expected.md` en blanco.

```bash
adb pull /sdcard/Android/data/com.agustin.tiza/files/fixtures ./fixtures
```

Después se completa cada `expected.md` **mirando la foto, no la respuesta del modelo**: copiar
la respuesta del modelo mide al modelo contra sí mismo. Mientras el archivo esté sin completar,
el runner saltea el caso y lo dice.

Un bug que salió de hacer este flujo en serio: el export usaba `File.copy` para la foto, que
**hereda los permisos** del archivo de caché del picker (`-rw-------`). El archivo aparecía en
la carpeta pero `adb pull` fallaba con "Permission denied" sin dar ninguna pista. Ahora escribe
los bytes.

### Resultados · primera corrida, 1 caso

Con `gemini-3.5-flash-lite`, sobre **un** caso: la imagen sintética del paso 3. Los tres
serializadores × los dos modos de salida:

| serializador | modo | título | bullets P/R | actions P/R | owners | descartes | tokens | latencia |
|---|---|---|---|---|---|---|---|---|
| plain | schema | 1/1 | 100% / 100% | 100% / 100% | 100% | 0 | 245→205 | 2148 ms |
| plain | markdown libre | 1/1 | 100% / 100% | 100% / 100% | 100% | 0 | 277→60 | 651 ms |
| coords | schema | 1/1 | 100% / 100% | 100% / 100% | 100% | 0 | 411→205 | 1196 ms |
| coords | markdown libre | 1/1 | 100% / 100% | 100% / 100% | 100% | 0 | 443→60 | 671 ms |
| columns | schema | 1/1 | 100% / 100% | 100% / 100% | 100% | 0 | 411→205 | 1242 ms |
| columns | markdown libre | 1/1 | 100% / 100% | 100% / 100% | 100% | 0 | 443→60 | 727 ms |

**Las seis configuraciones empatan en 100%.** Eso no dice que todas sean equivalentes: dice
que **este caso no discrimina**. Texto impreso, OCR sin un solo error, dos columnas y siete
renglones — cualquiera de los caminos lo resuelve. Es un efecto techo, y una eval saturada no
mide nada.

Leerlo así importa: la conclusión honesta de esta tabla **no** es "las coordenadas funcionan",
es "sobre este caso las coordenadas no compran nada, y cuestan". La segunda corrida, más
abajo, con casos difíciles, da vuelta esa lectura — que es la razón por la que las dos quedan
en el README en vez de sólo la última.

#### Lo que sí se puede concluir

Toda la diferencia está en el costo, y esos números sí son reales:

- **Las coordenadas cuestan 166 tokens de entrada por foto** (245 → 411, un 68% más) para un
  resultado idéntico. `columns` cuesta exactamente lo mismo que `coords`: cambia el orden, no
  el volumen.
- **El schema cuesta 3,4× los tokens de salida** que el markdown libre (205 → 60), porque el
  JSON es más verboso que el markdown. Y la salida es lo caro: la lista de precios de Gemini
  para Flash cobra la salida 5× la entrada.
- Pesando la salida 5×, la configuración más barata (`plain` + markdown libre) sale ~577
  unidades y la más cara (`columns` + schema) ~1436: **2,5× de diferencia por la misma nota.**
- **La latencia acompaña**: el schema aproximadamente duplica el tiempo, consistente con los
  tokens de salida. Los 2148 ms de la primera fila son el arranque en frío, no una diferencia
  real entre configuraciones.
- **Cero descartes de validación** en las seis. Los 2 que aparecen con `--fake` son las entradas
  inválidas que la respuesta simulada trae a propósito; el modelo real cumplió el schema.

Y una confirmación de algo afirmado en el paso 5: **el prompt con schema es más corto**. 245
contra 277 tokens de entrada sobre la misma serialización — las instrucciones de formato que se
borraron pesan 32 tokens por llamada, y el `responseSchema` no las compensa.

Sobre el precio absoluto por foto no digo nada: no verifiqué la tarifa de Flash-Lite, sólo la de
Flash. Las relaciones de arriba no dependen de eso.

### Resultados · segunda corrida, 5 casos

Con los cinco casos de layout. La primera pasada perdió 12 de 30 llamadas con 429 del tier
gratuito; después de agregarle throttling al runner, cinco de las seis configuraciones
completaron. El costo pesa la salida 5×, que es la relación que publica Gemini para Flash:

| serializador | modo | n | título | bullets P/R | actions P/R | tokens | costo rel. |
|---|---|---|---|---|---|---|---|
| plain | markdown libre | 5/5 | 5/5 | 100% / 100% | 100% / 100% | 262→46 | **492** |
| plain | schema | 5/5 | **4/5** | 100% / **88%** | **50%** / 100% | 230→136 | 910 |
| coords | markdown libre | 5/5 | 5/5 | 100% / 100% | 100% / 100% | 409→44 | 629 |
| columns | markdown libre | 5/5 | 5/5 | 100% / 100% | 100% / 100% | 409→44 | 629 |
| coords | schema | 5/5 | 5/5 | 100% / 100% | 100% / 100% | 377→154 | 1147 |
| columns | schema | 5/5 | 5/5 | 100% / 100% | 100% / 100% | 377→154 | 1147 |

**Predije que las seis darían 100% y me equivoqué.** Cinco de seis dan 100%; la que falla no
es la que esperaba, y la más barata está entre las que aciertan.

#### El primer indicio de que las coordenadas sirven

`plain` + schema es el único que se degrada: pierde un título, el 12% de los bullets, y —lo
más interesante— **inventa action items**. La precisión del 50% con recall del 100% significa
que devolvió seis donde se esperaban tres: en casos que no tienen ninguno, se los inventó.

El mecanismo es plausible: el schema exige decidir si cada renglón es un bullet o un action
item, y sin información posicional el modelo no tiene con qué distinguirlos, así que adivina.
Con markdown libre no se siente obligado a llenar el campo. Y con coordenadas el problema
desaparece.

Es exactamente lo contrario de lo que decía la corrida de un caso, y era esperable: ahí no
había nada que distinguir.

#### El orden no le importa al modelo, y eso deja al XY-cut sin trabajo

`coords` y `columns` dieron **exactamente los mismos números en los dos modos**: 377→154 con
schema y 409→44 con markdown libre, 100% en todo. Idénticos, dos veces. Y no son
serializaciones parecidas: tienen la misma información en un orden muy distinto —`coords`
acumula 14 saltos de más y 26 inversiones, `columns` 2 y 2—.

Es la confirmación más limpia posible de que **el modelo es indiferente al orden cuando tiene
las coordenadas**: las lee y reordena por su cuenta. Lo que le falta a `plain` no es orden, es
información posicional, y por eso es el único que se rompe.

De ahí salen dos consecuencias que no me favorecen y van escritas igual:

- **El XY-cut resuelve un problema que el modelo no tenía.** Es la parte del proyecto que más
  trabajo llevó —el algoritmo, el umbral, ocho tests de layout— y su ganancia medible sobre
  `coords` es cero.
- **La métrica de orden no predice la calidad**, que era lo único que la haría útil como
  reemplazo barato de la eval con tokens. Sirve para depurar una serialización, no para
  decidir cuál usar.

Y la conclusión de costo es todavía más incómoda: **la configuración más barata es también
perfecta**. `plain` + markdown libre saca 100% en todo con 492 unidades de costo; la más cara
que también saca 100% cuesta 2,3× eso.

Con la matriz completa, la lectura útil es esta: **las coordenadas no son una mejora de
calidad, son el precio del structured output.**

| lo que querés | qué necesitás | costo |
|---|---|---|
| markdown y nada más | `plain` + markdown libre | 492 |
| datos tipados | coordenadas + schema, obligatorio | 1147 |

Sin posiciones el schema inventa action items, así que si querés datos tipados pagás las
coordenadas. Si te alcanza con markdown, no las necesitás. Eso es una decisión de producto con
precio medido, que es lo que la tabla tenía que dar y no daba cuando todo empataba en 100%.

Dos salvedades que hacen falta para no sobreinterpretar:

- Estos son cinco casos de **texto impreso** donde el OCR casi no falla. La premisa de las
  coordenadas es que en un pizarrón real el orden de lectura de MLKit es basura y las
  posiciones son lo único que salva la estructura. Eso sigue sin probarse.
- El schema no compite sólo por costo: devuelve **datos tipados**, que es lo que permite el
  render nativo y cualquier cosa que venga después. Que salga más caro no lo vuelve
  equivocado, lo vuelve una decisión con precio conocido — que es exactamente lo que la tabla
  tenía que dar.

#### Lo que se arregló del runner

Dos defectos que salieron de esta corrida:

- **No había throttling ni reintentos.** 30 llamadas seguidas superan el límite por minuto del
  tier gratuito. Ahora hay una pausa de 4,5 s por defecto (`--delay`) y reintentos con espera
  creciente ante 429 y 5xx. Una cuota agotada no es un fallo del modelo, y contarla como tal
  mezclaba infraestructura con calidad.
- **La tabla invitaba a comparar filas incomparables.** Ahora la `n` se imprime como fracción,
  las filas incompletas van marcadas con ⚠ y hay un aviso explícito de que no se comparan.

#### Qué queda sin medir

El eje del **layout** está cerrado hasta donde se puede sintetizar. Los cinco casos —generados
por [`scripts/generar_casos_layout.ps1`](scripts/generar_casos_layout.ps1) y pasados por la app
para tener las cajas reales de MLKit— discriminan, y la respuesta que dieron fue que el orden no
le importa al modelo.

Los otros dos ejes siguen con techo. Estos casos son **texto impreso**: el OCR casi no falla y
los modelos no se diferencian entre sí. Para moverlos hace falta letra manuscrita real, con
reflejos, foco irregular y renglones torcidos.

La distinción importa porque decide qué se puede medir sin salir de la máquina:

| eje | qué necesita | estado |
|---|---|---|
| serializador (layout) | geometría difícil, que se puede sintetizar | medido |
| OCR (calidad de lectura) | fotos reales de letra manuscrita | pendiente |
| modelo y modo de salida | contenido ambiguo de estructurar | pendiente |

El golden set de verdad son 15-20 fotos reales, y eso no lo puede hacer el código.

## Los estados de error

La especificación pide tres visibles. Salieron siete, porque el camino del modelo tiene más
formas de fallar que las tres obvias, y cada una necesita una acción distinta.

**La regla es que ningún fallo sea un callejón.** [`recoveriesFor`](lib/ui/screen_error.dart)
es una función pura que mapea cada tipo de fallo a las salidas que tiene el usuario, y hay un
test que recorre el enum entero y falla si alguno queda sin ninguna — incluidos los que se
agreguen después de hoy. Ese es el error más fácil de cometer acá.

Las salidas no son intercambiables, y ahí está el criterio:

| Fallo | Salidas | Por qué esas |
|---|---|---|
| Falta la key | configurarla · ver una respuesta simulada | Reintentar sin key vuelve a fallar igual: ofrecerlo sería mentir sobre lo que va a pasar |
| Key rechazada | configurarla | Lo mismo |
| Cuota agotada | reintentar · elegir otro modelo | Los límites del tier gratuito son **por modelo**, así que bajar de modelo es una salida real |
| Sin red | reintentar | |
| Servidor caído | reintentar | |
| Contenido bloqueado | otra foto | Los filtros son deterministas sobre el mismo contenido: reintentar da el mismo bloqueo |
| Respuesta mal formada | reintentar | Suele ser un tropiezo del modelo, no algo determinista |

**El detalle del proveedor no se descarta.** Arranca plegado detrás de un "ver el detalle",
porque el mensaje amable alcanza para casi todo, pero cuando no alcanza es lo único con lo
que se entiende qué pasó. Tirarlo para que la pantalla quede limpia es el error más común de
los estados de error. En el caso del JSON que no valida, el detalle es **el texto que
devolvió el modelo** —recortado a 300 caracteres—, que antes se perdía en el `catch`.

**El OCR sin texto no es una nota de error, es un estado.** Es un resultado legítimo del
camino gratuito, y el panel de métricas lo demuestra mostrando 0 renglones y el tiempo que
tardó. Lo que necesita el usuario ahí no es una disculpa sino saber por qué pudo pasar, así
que [`NoTextState`](lib/ui/widgets/no_text_state.dart) lista las cuatro causas de más a menos
frecuente. La última —"la letra es cursiva muy ligada: MLKit está entrenado sobre
imprenta"— es una limitación real que conviene decir en vez de esconder.

<img src="capturas/sin-texto.png" width="330" alt="Estado sin texto: 0 renglones, confianza s/d, y las cuatro causas probables">

El panel de arriba es la prueba de que el camino gratuito corrió: 1021 ms, 0 renglones,
confianza `s/d`. Sin esos números, "no encontré texto" y "algo se rompió" se ven igual.

### Cómo se verificó cada uno

| Estado | Cómo |
|---|---|
| OCR sin texto | Una imagen sin texto empujada al emulador. 699 ms, 0 renglones, confianza `s/d` |
| Sin red | `adb shell svc wifi disable` + `svc data disable`, con una key guardada para pasar el chequeo previo |
| Key rechazada | Llamada real a la API con una key inválida (ver más arriba) |
| JSON que no valida | Sólo por tests: forzarlo desde la UI necesitaría una key válida y un modelo que se descarrile a pedido |

El de sin red dejó la captura más útil del proyecto:

<img src="capturas/sin-red.png" width="330" alt="Sin conexión: el error muestra Failed host lookup y el panel del OCR marca 1289 ms y 11 renglones">

El error dice `Failed host lookup: 'generativelanguage.googleapis.com'` y, arriba, **el panel
del OCR muestra 1097 ms y 11 renglones**. La foto se eligió y se reconoció con la red ya
apagada: el camino barato funcionó offline de punta a punta, y lo único que falló fue el
pedazo que necesitaba internet.

## Diseño

Dos superficies opuestas: **papel** en claro, **pizarrón** en oscuro. Lo que fotografiás
es un pizarrón y lo que obtenés es una hoja, así que el modo oscuro es el único lugar
donde eso se puede decir sin escribirlo. Los tokens viven en un `ThemeExtension`
([`lib/theme/tiza_theme.dart`](lib/theme/tiza_theme.dart)) con nombres semánticos —`ink`,
`paper`, `rule`, `accent`— para que ningún widget sepa sobre qué material está dibujando.

Las tipografías son las genéricas de la plataforma, `serif` y `monospace`, que Android
resuelve a Noto Serif y Roboto Mono: contraste tipográfico real sin bajar una fuente ni
sumar una dependencia.

Dos elementos hacen trabajo más allá de la decoración:

- **El panel de métricas** está arriba, no al pie. La tesis del proyecto es que el trabajo
  caro se evita midiendo, y latencia, renglones y confianza son la evidencia.
- **El contador de caracteres** sobre la serialización es el proxy más directo del costo en
  tokens. Tenerlo a la vista mientras se comparan formatos evita elegir el más rico sin
  mirar lo que cuesta: sobre la misma foto `plain` da 191 caracteres y `coords` 499, unas
  2,6 veces más. Que el formato con layout gane en calidad todavía hay que demostrarlo;
  que cuesta 2,6 veces más ya se sabe.

El ícono se genera con [`scripts/generar_icono.ps1`](scripts/generar_icono.ps1), que
produce los mipmaps full-bleed para API 24-25 y el foreground del adaptive icon para 26+.

## Hallazgos del paso 3

Probado con una imagen sintética de 1200×1600: texto impreso en dos columnas y tres
tamaños de fuente, reproducible con
[`scripts/generar_imagen_prueba.ps1`](scripts/generar_imagen_prueba.ps1). Es un caso
determinista donde el OCR no falla, para aislar los problemas de la serialización de los
del OCR. MLKit leyó los 11 renglones sin un solo error, con 88% de confianza promedio.

**1. La línea de base agrupa las columnas mejor que el serializador "mejorado".**

MLKit devuelve los bloques agrupados por columna: primero toda la columna izquierda,
después toda la derecha. Ordenar por `y` —lo que parecía la mejora obvia— **destruye ese
agrupamiento** e intercala las dos columnas:

| `plain` | `coords` |
|---|---|
| Sprint planning | Sprint planning |
| Objetivos | Action items |
| cerrar el checkout | Objetivos |
| migrar la base | cerrar el checkout |
| medir latencia | Ana: revisar metricas |
| Riesgos | migrar la base |
| el proveedor no responde | Beto: deploy el viernes |
| Action items | Cami: hablar con legales |
| Ana: revisar metricas | medir latencia |
| Beto: deploy el viernes | Riesgos |
| Cami: hablar con legales | el proveedor no responde |

Ninguno de los dos gana en todo: `plain` conserva el agrupamiento pero tira la jerarquía;
`coords` recupera tamaño e indentación pero rompe el orden.

**Resuelto** por `columns` (XY-cut) en la métrica de orden — y después medido contra el modelo,
donde resultó **no importar**: `coords` y `columns` dan resultados idénticos. El desorden que
este hallazgo señalaba no le molestaba al modelo. Está más abajo, con los números.

**2. El alto del bounding box es una señal de tamaño más ruidosa de lo esperado.**

MLKit devuelve la caja del renglón, y su alto depende de si hay ascendentes y
descendentes, no del cuerpo de la fuente. Tres renglones en el **mismo tamaño** (34pt):

| texto | alto relativo | por qué |
|---|---|---|
| Riesgos | 65 | descendente (`g`) |
| Objetivos | 62 | descendente (`j`) |
| Action items | 52 | ninguna |

Lo mismo en los bullets, todos en 22pt: de 31 (`Ana: revisar metricas`) a 46
(`Cami: hablar con legales`). Es ±20% de ruido sobre texto impreso perfecto.

Acá los rangos todavía no se solapan (títulos 52–65 vs bullets 31–46), pero el margen es
de 6 puntos. Con letra manuscrita, donde el tamaño ya varía renglón a renglón, es
probable que se solapen. Si pasa, la alternativa es medir la altura de la x —el cuerpo
sin ascendentes ni descendentes— usando `TextElement`, o directamente dejar de usar el
tamaño como señal y apoyarse sólo en `x` para la jerarquía.

**3. La latencia del OCR en el emulador no es la del dispositivo.**

| corrida | latencia |
|---|---|
| primera de una instalación nueva | 4802–14051 ms |
| siguientes | 1846 ms |

Medido en el emulador Pixel 9a (x86_64, APK de debug). El documento estima ~50 ms; ese
número hay que verificarlo en el teléfono físico antes de ponerlo en ningún lado. La
medición está en pantalla justamente para no tener que afirmarla de memoria.

## Correr

```bash
flutter test
```

104 tests, todos en Dart puro o con `flutter_test`: corren en la máquina, sin emulador, sin
red y sin API key.

Ocho de ellos, en [`test/xy_cut_test.dart`](test/xy_cut_test.dart), son layouts hostiles
para el XY-cut con geometría escrita a mano: tres columnas, columnas desparejas, columnas
que arrancan a distinta altura, bullets indentados, y dos casos que **documentan límites
conocidos en vez de esconderlos** — cuando los rangos de `x` se solapan no hay canaleta y
degrada al orden por `y`, y con una canaleta de menos del 4% del ancho las columnas se
intercalan. Bajar ese umbral arreglaría el segundo y rompería el de los bullets
indentados, así que la salida no es tocar el número: es una señal de layout distinta de la
distancia. Si aparece en fotos reales, ahí se decide.

Son tests del algoritmo, no fixtures del golden set: sin imagen y sin MLKit. La distinción
importa, porque el eje del serializador es sobre layout y el layout se puede hacer difícil
sin letra manuscrita. Lo que sí necesita fotos reales es la calidad del OCR y la
comparación entre modelos.

```bash
flutter run
```

Requiere Android; MLKit no corre en Windows ni en web. `minSdk` está fijado en 24 en
`android/app/build.gradle.kts`.

```bash
flutter build apk --release
```

El build de release necesita
[`android/app/proguard-rules.pro`](android/app/proguard-rules.pro), y vale contar por qué: el
plugin de MLKit referencia los cinco reconocedores de script —latín, chino, devanagari,
japonés, coreano— desde su código Java, pero el pubspec sólo trae el de latín. R8 ve
referencias a clases que no están en el classpath y **falla el build**. La app usa sólo
latín, así que son código muerto y alcanza con cuatro `-dontwarn`. La alternativa era sumar
las cuatro dependencias que faltan y cargar decenas de MB de modelos que nunca se usan.

El APK pesa 77 MB porque incluye las tres ABIs y el modelo de latín va embebido en el
binario. Con `--split-per-abi` baja a un tercio.

Dos de los tests son regresión de un bug que vale contar: los paneles usan `Row` con
`CrossAxisAlignment.stretch` para que los separadores verticales lleguen de arriba abajo,
y viven como hijos **no flexibles** de una `Column`, que les pasa altura sin límite.
Estirar contra infinito hace fallar el layout, y el síntoma no es una excepción visible
sino que **la pantalla del resultado se dibuja en blanco**. La corrección es
`IntrinsicHeight`; los tests montan cada panel como hijo directo de una `Column` para
reproducir exactamente esa condición de borde.

## Terminado cuando

El checklist de la especificación de la fase 1, y qué falta:

| | |
|---|---|
| Foto de un pizarrón real → markdown usable | **falta** — necesita el teléfono físico |
| Los tres estados de error manejados y visibles | listo |
| Golden set de 15+ casos y un runner que lo corra | runner listo, 5 casos sintéticos, **faltan las fotos** |
| README con la tabla de al menos dos configuraciones | listo, hay seis |

Dos de cuatro, y los dos que faltan son el mismo trabajo: sacar fotos reales con el teléfono.

## Licencia

MIT — ver [`LICENSE`](LICENSE).

## Fuera de alcance en v1

Sin cuentas, sin historial, sin backend, sin multi-idioma, sin edición de la imagen.

La fase 2 —fotos de diagramas a Mermaid, con un router que decida por foto si hace falta el
modelo de visión caro o alcanza con el camino barato— **no arranca hasta que la fase 1 tenga
su golden set**. Sin esa línea de base el router no tiene contra qué medirse, y el router es
todo el interés de esa fase.
