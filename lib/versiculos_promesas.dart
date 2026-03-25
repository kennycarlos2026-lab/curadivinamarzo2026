import 'dart:io';
import 'data_versiculos.dart';

String obtenerVersiculoDelDia() {
  final now = DateTime.now();
  final monthStr = now.month.toString().padLeft(2, '0');
  final dayStr = now.day.toString().padLeft(2, '0');
  final targetSuffix = '-$monthStr-$dayStr';

  // Find the verse for today's month and day (ignoring year to be safe for future years)
  Map<String, String>? verseMap;
  try {
    verseMap = versiculosData.firstWhere((element) {
      final dateStr = element['date'];
      return dateStr != null && dateStr.endsWith(targetSuffix);
    });
  } catch (e) {
    // Fallback if not found
    if (versiculosData.isNotEmpty) {
      verseMap = versiculosData.first;
    }
  }

  if (verseMap == null) {
    return "«Porque yo sé los pensamientos que tengo acerca de vosotros, dice Jehová, pensamientos de paz, y no de mal...» (Jeremías 29:11)";
  }

  // Determine language, defaulting to 'pt'
  String lang = 'pt';
  try {
    final locale = Platform.localeName;
    if (locale.startsWith('es')) {
      lang = 'es';
    } else if (locale.startsWith('en')) {
      lang = 'en';
    }
  } catch (_) {
    // Ignore error if Platform.localeName fails (e.g. web unsupported)
  }

  String text = '';
  String ref = '';

  if (lang == 'es') {
    text = verseMap['text_rv1909'] ?? '';
    ref = verseMap['reference_es'] ?? '';
  } else if (lang == 'en') {
    text = verseMap['text_kjv'] ?? '';
    ref = verseMap['reference_en'] ?? '';
  } else {
    // Default to PT
    text = verseMap['text_arc1911'] ?? '';
    ref = verseMap['reference_pt'] ?? '';
  }

  return "«$text» ($ref)";
}
