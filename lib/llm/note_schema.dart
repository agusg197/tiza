/// El `responseSchema` que se le manda a Gemini.
///
/// Va acá, como un mapa Dart y no interpolado dentro del cliente HTTP, por lo
/// mismo que el prompt: es una de las variables del paso 7 y tiene que poder
/// leerse y versionarse sola.
///
/// Dos cosas de la API que hay que tener presentes:
///
/// - Los tipos van en **mayúsculas** (`STRING`, `OBJECT`, `ARRAY`, `INTEGER`).
///   Es un enum de proto, no JSON Schema estándar, y en minúsculas devuelve 400.
/// - `propertyOrdering` no existe en OpenAPI: es una extensión de Google, y sirve
///   porque el modelo genera en ese orden. No es cosmético — decidir el
///   encabezado antes que los bullets da mejores resultados que al revés.
library;

/// El schema está deliberadamente **chato**: dos niveles y nada más.
///
/// La especificación de la fase 1 lo pide en esas palabras —"cuanto más anidado
/// el schema, más se equivoca el modelo"— y `depth` es la concesión: permite
/// expresar jerarquía sin anidar la estructura, así que el error posible es un
/// número mal elegido en vez de un árbol mal armado.
const Map<String, dynamic> kNoteResponseSchema = {
  'type': 'OBJECT',
  'properties': {
    'title': {
      'type': 'STRING',
      'nullable': true,
      'description': 'Título general de la nota. null si el pizarrón no tiene uno.',
    },
    'sections': {
      'type': 'ARRAY',
      'description': 'Bloques de contenido, en el orden en que se leen.',
      'items': {
        'type': 'OBJECT',
        'properties': {
          'heading': {
            'type': 'STRING',
            'description': 'Encabezado del bloque, tal como está escrito.',
          },
          'depth': {
            'type': 'INTEGER',
            'description':
                'Nivel de anidamiento: 0 para las secciones de primer nivel, '
                '1 para una subsección, y así. No pasar de 3.',
          },
          'bullets': {
            'type': 'ARRAY',
            'description': 'Los ítems del bloque, uno por renglón del pizarrón.',
            'items': {'type': 'STRING'},
          },
        },
        'required': ['heading', 'depth', 'bullets'],
        'propertyOrdering': ['heading', 'depth', 'bullets'],
      },
    },
    'actionItems': {
      'type': 'ARRAY',
      'description': 'Tareas pendientes. Vacío si no hay ninguna.',
      'items': {
        'type': 'OBJECT',
        'properties': {
          'text': {
            'type': 'STRING',
            'description': 'La tarea, sin el nombre del responsable adelante.',
          },
          'owner': {
            'type': 'STRING',
            'nullable': true,
            'description':
                'Responsable, si el texto lo indica. null si no lo indica.',
          },
        },
        'required': ['text'],
        // `text` antes que `owner`: el modelo genera en este orden, y decidir el
        // responsable antes de haber escrito la tarea lo lleva a inventar dueños.
        'propertyOrdering': ['text', 'owner'],
      },
    },
  },
  'required': ['sections', 'actionItems'],
  'propertyOrdering': ['title', 'sections', 'actionItems'],
};
