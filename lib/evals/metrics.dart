/// Las métricas del golden set.
///
/// La especificación es explícita en que **no se busca exactitud carácter por
/// carácter**: hay muchas formas correctas de escribir la misma nota. Lo que se
/// mide es si el contenido terminó en el lugar correcto.
library;

import '../llm/structured_note.dart';

/// Normaliza un texto antes de compararlo.
///
/// Saca acentos, mayúsculas, puntuación de los extremos y espacios repetidos.
///
/// La decisión discutible es **sacar los acentos**, y va acá anotada: el OCR
/// pierde tildes con frecuencia —en la foto de prueba devolvió "metricas"— y el
/// prompt le prohíbe al modelo corregir lo que leyó el OCR. Si la comparación
/// fuera sensible a la tilde, el golden set escrito a mano con "métricas" marcaría
/// un fallo de estructuración donde en realidad hubo un fallo de OCR. Son dos
/// cosas distintas y se miden por separado: la calidad del OCR ya está medida por
/// la confianza que reporta MLKit.
String normalizeForMatch(String text) {
  const withAccents = 'áàäâãéèëêíìïîóòöôõúùüûñç';
  const without = 'aaaaaeeeeiiiiooooouuuunc';

  final lower = text.toLowerCase();
  final buffer = StringBuffer();
  for (final char in lower.split('')) {
    final index = withAccents.indexOf(char);
    buffer.write(index >= 0 ? without[index] : char);
  }

  return buffer
      .toString()
      .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

/// Qué tan bien el orden de un serializador respeta los bloques de la nota.
///
/// Es la métrica más barata del proyecto: **no llama al modelo**. Sale de comparar
/// el orden en que el serializador presenta los renglones contra los bloques del
/// golden set, y con eso alcanza para saber si una idea de layout mejora o empeora
/// antes de gastar un solo token.
///
/// Un serializador perfecto recorre cada bloque de punta a punta antes de pasar al
/// siguiente, así que hace exactamente `bloques - 1` saltos. Cada salto de más es
/// una vez que intercaló contenido de dos bloques distintos: exactamente el
/// problema que se documentó en el paso 3 con las dos columnas.
class ReadingOrderScore {
  const ReadingOrderScore({
    required this.groups,
    required this.switches,
    required this.mapped,
    required this.unmapped,
    required this.inversions,
  });

  /// Bloques del golden set que aparecieron en la serialización.
  final int groups;

  /// Transiciones de bloque observadas al recorrer el orden serializado.
  final int switches;

  final int mapped;

  /// Renglones que no se pudieron atribuir a ningún bloque. Suelen ser errores de
  /// OCR que no están en el golden set; se ignoran para el conteo de saltos.
  final int unmapped;

  /// Pares de bloques que aparecen en orden invertido respecto del golden set.
  ///
  /// [switches] mide **contigüidad** y no secuencia, y eso resultó ser un punto
  /// ciego real: un orden que entrega los bloques enteros pero cambiados de lugar
  /// —el último bloque en el medio, por ejemplo— sacaba saltos perfectos. Cero
  /// inversiones significa que además de venir enteros, vienen en el orden en que
  /// una persona los leería.
  final int inversions;

  int get ideal => groups == 0 ? 0 : groups - 1;
  int get extra => switches - ideal;

  /// Bloques enteros **y** en orden.
  bool get perfect => extra == 0 && inversions == 0;
}

/// Evalúa el orden de una serialización contra los bloques esperados.
ReadingOrderScore scoreReadingOrder({
  required StructuredNote expected,
  required List<String> orderedTexts,
}) {
  // Cada texto del golden set apunta al bloque al que pertenece. Los action items
  // se registran también con el responsable adelante, porque así es como aparecen
  // en el renglón del pizarrón: "Ana: revisar metricas".
  final groupOf = <String, int>{};
  var next = 0;

  void register(String text, int group) {
    final key = normalizeForMatch(text);
    if (key.isNotEmpty) groupOf.putIfAbsent(key, () => group);
  }

  if (expected.title != null) register(expected.title!, next++);

  for (final section in expected.sections) {
    final group = next++;
    register(section.heading, group);
    for (final bullet in section.bullets) {
      register(bullet, group);
    }
  }

  if (expected.actionItems.isNotEmpty) {
    final group = next++;
    for (final item in expected.actionItems) {
      register(item.text, group);
      if (item.owner != null) register('${item.owner} ${item.text}', group);
    }
  }

  final seen = <int>[];
  var unmapped = 0;
  for (final text in orderedTexts) {
    final group = groupOf[normalizeForMatch(text)];
    if (group == null) {
      unmapped++;
    } else {
      seen.add(group);
    }
  }

  var switches = 0;
  // La secuencia de bloques, uno por tramo: [0,1,1,1,3,3,2] queda como [0,1,3,2].
  final runs = <int>[];
  for (var i = 0; i < seen.length; i++) {
    if (i == 0 || seen[i] != seen[i - 1]) {
      switches += i == 0 ? 0 : 1;
      runs.add(seen[i]);
    }
  }

  // Los grupos están numerados en el orden del golden set, así que contar
  // inversiones sobre los tramos alcanza para saber si la secuencia se respetó.
  var inversions = 0;
  for (var i = 0; i < runs.length; i++) {
    for (var j = i + 1; j < runs.length; j++) {
      if (runs[i] > runs[j]) inversions++;
    }
  }

  return ReadingOrderScore(
    groups: seen.toSet().length,
    switches: switches,
    mapped: seen.length,
    unmapped: unmapped,
    inversions: inversions,
  );
}

/// Precision y recall sobre un conjunto de textos.
class SetScore {
  const SetScore({
    required this.expected,
    required this.actual,
    required this.matched,
    required this.missing,
    required this.spurious,
  });

  final int expected;
  final int actual;
  final int matched;

  /// Lo que estaba en el golden set y no apareció.
  final List<String> missing;

  /// Lo que apareció y no estaba en el golden set. Suele ser texto reciclado de
  /// otra sección, o un renglón que el modelo partió en dos.
  final List<String> spurious;

  /// De lo que devolvió, cuánto era correcto.
  double get precision => actual == 0 ? (expected == 0 ? 1 : 0) : matched / actual;

  /// De lo que se esperaba, cuánto encontró.
  double get recall => expected == 0 ? 1 : matched / expected;

  double get f1 => (precision + recall) == 0
      ? 0
      : 2 * precision * recall / (precision + recall);
}

/// Compara dos listas de textos como multiconjuntos normalizados.
SetScore compareTexts(List<String> expected, List<String> actual) {
  final pending = [...actual];
  final missing = <String>[];
  var matched = 0;

  for (final want in expected) {
    final key = normalizeForMatch(want);
    final index = pending.indexWhere((got) => normalizeForMatch(got) == key);
    if (index >= 0) {
      pending.removeAt(index);
      matched++;
    } else {
      missing.add(want);
    }
  }

  return SetScore(
    expected: expected.length,
    actual: actual.length,
    matched: matched,
    missing: missing,
    spurious: pending,
  );
}

/// El resultado de evaluar una foto con una configuración.
class NoteScore {
  const NoteScore({
    required this.titleExpected,
    required this.titleMatched,
    required this.bullets,
    required this.actionItems,
    required this.ownersExpected,
    required this.ownersMatched,
  });

  /// Si el golden set tenía título. Sin esto, "acertó el título" sobre una nota
  /// sin título sería un acierto gratis.
  final bool titleExpected;
  final bool titleMatched;

  final SetScore bullets;
  final SetScore actionItems;

  /// Responsables: de los action items que se emparejaron, cuántos tenían el mismo
  /// owner. Se cuenta aparte porque un action item bien detectado con el dueño
  /// equivocado es un error distinto —y menos grave— que no detectarlo.
  final int ownersExpected;
  final int ownersMatched;

  double get ownerAccuracy =>
      ownersExpected == 0 ? 1 : ownersMatched / ownersExpected;
}

/// Evalúa una nota contra la esperada.
NoteScore scoreNote({
  required StructuredNote expected,
  required StructuredNote actual,
}) {
  final titleExpected = expected.title != null;
  final titleMatched = titleExpected &&
      actual.title != null &&
      normalizeForMatch(expected.title!) == normalizeForMatch(actual.title!);

  // Los bullets se comparan aplanados, sin exigir que hayan caído en la misma
  // sección. Es a propósito: la especificación pide contar bullets encontrados
  // contra esperados, y penalizar dos veces el mismo error —una por el bullet y
  // otra por la sección— haría que los números no se puedan leer.
  final bullets = compareTexts(
    [for (final section in expected.sections) ...section.bullets],
    [for (final section in actual.sections) ...section.bullets],
  );

  final actions = compareTexts(
    [for (final item in expected.actionItems) item.text],
    [for (final item in actual.actionItems) item.text],
  );

  var ownersExpected = 0;
  var ownersMatched = 0;
  for (final want in expected.actionItems) {
    if (want.owner == null) continue;
    ownersExpected++;

    final key = normalizeForMatch(want.text);
    final got = actual.actionItems.firstWhere(
      (item) => normalizeForMatch(item.text) == key,
      orElse: () => const ActionItem(text: ''),
    );
    if (got.owner != null &&
        normalizeForMatch(got.owner!) == normalizeForMatch(want.owner!)) {
      ownersMatched++;
    }
  }

  return NoteScore(
    titleExpected: titleExpected,
    titleMatched: titleMatched,
    bullets: bullets,
    actionItems: actions,
    ownersExpected: ownersExpected,
    ownersMatched: ownersMatched,
  );
}
