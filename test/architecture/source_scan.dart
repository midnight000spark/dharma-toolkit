/// Лексический скан исходников для architecture-guard-тестов.
///
/// Guard'ы читают исходники как текст, поэтому «наивный» разбор спотыкается на
/// трёх местах (находки ревью tests-quality-1): многострочные директивы,
/// блочные комментарии и строковые литералы, содержащие текст, похожий на код.
/// Здесь — единый мини-лексер: он убирает комментарии и (по выбору) содержимое
/// строк, **сохраняя переводы строк**, чтобы номера строк в отчётах не ехали.
library;

/// Удалить `//`- и `/* */`-комментарии, сохранив строковые литералы: для
/// разбора `import`/`export` строки — цель (URI), их нельзя терять.
String stripComments(String source) => _scan(source, keepStrings: true);

/// Удалить комментарии **и содержимое строковых литералов**: для поиска
/// конструкций уровня кода (`expect(true, …)`), чтобы описание антипаттерна
/// в строке/комментарии не выглядело как код.
String stripNonCode(String source) => _scan(source, keepStrings: false);

String _scan(String source, {required bool keepStrings}) {
  final out = StringBuffer();
  var i = 0;
  final n = source.length;

  while (i < n) {
    final c = source[i];

    // //-комментарий: до конца строки.
    if (c == '/' && i + 1 < n && source[i + 1] == '/') {
      while (i < n && source[i] != '\n') {
        i++;
      }
      out.write(' ');
      continue;
    }

    // /* */ -комментарий: переводы строк сохраняем.
    if (c == '/' && i + 1 < n && source[i + 1] == '*') {
      i += 2;
      while (i < n && !(source[i] == '*' && i + 1 < n && source[i + 1] == '/')) {
        out.write(source[i] == '\n' ? '\n' : ' ');
        i++;
      }
      if (i < n) {
        out.write(' ');
        i += 2;
      }
      continue;
    }

    // Строковый литерал (в т.ч. тройной): содержимое — по флагу keepStrings.
    if (c == "'" || c == '"') {
      final quote = c;
      final triple =
          i + 2 < n && source[i + 1] == quote && source[i + 2] == quote;
      final delim = triple ? quote + quote + quote : quote;
      if (keepStrings) out.write(delim);
      i += delim.length;
      while (i < n) {
        if (source[i] == r'\' && i + 1 < n) {
          if (keepStrings) {
            out.write(source[i]);
            out.write(source[i + 1]);
          }
          i += 2;
          continue;
        }
        if (_startsWithAt(source, i, delim)) {
          if (keepStrings) out.write(delim);
          i += delim.length;
          break;
        }
        if (keepStrings) {
          out.write(source[i]);
        } else {
          out.write(source[i] == '\n' ? '\n' : ' ');
        }
        i++;
      }
      continue;
    }

    out.write(c);
    i++;
  }
  return out.toString();
}

bool _startsWithAt(String source, int at, String pattern) {
  if (at + pattern.length > source.length) return false;
  for (var k = 0; k < pattern.length; k++) {
    if (source[at + k] != pattern[k]) return false;
  }
  return true;
}
