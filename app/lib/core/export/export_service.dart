import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import '../calculation/calculation_engine.dart';
import '../calculation/models/calculation_result.dart';
import '../calculation/models/dish.dart';
import 'docx_blank_generator.dart';
import 'pdf_blank_generator.dart';
import 'xlsx_blank_generator.dart';

enum ExportType { pdf, docx, xlsx }

class ExportService {
  static String _pluralDishes(int count) {
    final n = count.abs();
    final mod100 = n % 100;
    final mod10 = n % 10;
    if (mod100 >= 11 && mod100 <= 14) return '$count блюд';
    if (mod10 == 1) return '$count блюдо';
    if (mod10 >= 2 && mod10 <= 4) return '$count блюда';
    return '$count блюд';
  }

  /// Remove abandoned staging directories after a crash. Never follow links or
  /// touch the plugin-owned share_plus cache / user documents.
  static Future<void> pruneAbandonedExports(Directory root,
      {DateTime? now, Duration maxAge = const Duration(days: 1)}) async {
    if (!await root.exists()) return;
    final cutoff = (now ?? DateTime.now()).subtract(maxAge);
    await for (final entry in root.list(followLinks: false)) {
      if (entry is! Directory || !p.basename(entry.path).startsWith('blank_'))
        continue;
      final stat = await entry.stat();
      if (stat.modified.isBefore(cutoff)) {
        try {
          await entry.delete(recursive: true);
        } on FileSystemException {/* best effort */}
      }
    }
  }

  /// Bounded UTF-8 filename component; the complete title remains inside the document.
  static String fileBaseTitle(String title) {
    var cleaned =
        title.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f\x7f]'), '_').trim();
    cleaned = cleaned.replaceAll(RegExp(r'[. ]+$'), '');
    final buffer = StringBuffer();
    var bytes = 0;
    for (final rune in cleaned.runes) {
      final character = String.fromCharCode(rune);
      final length = utf8.encode(character).length;
      if (bytes + length > 80) break;
      buffer.write(character);
      bytes += length;
    }
    cleaned = buffer.toString().replaceAll(RegExp(r'[. ]+$'), '');
    if (cleaned.isEmpty) return 'Бланк_расчета';
    if (RegExp(r'^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\.|$)',
            caseSensitive: false)
        .hasMatch(cleaned)) {
      return '_$cleaned';
    }
    return cleaned;
  }

  /// Прямая печать или встроенный просмотр PDF на Android
  static Future<void> printPdf(Dish dish) async {
    final pdfBytes = await PdfBlankGenerator.generate(dish);
    final title = dish.title.isNotEmpty ? dish.title : 'Бланк_расчета';
    await Printing.layoutPdf(
      onLayout: (format) async => pdfBytes,
      // Same sanitization as file exports: the print job name can become the
      // suggested filename of a "Save as PDF" destination.
      name: '${fileBaseTitle(title)}.pdf',
    );
  }

  /// Экспорт и открытие системного диалога "Поделиться" для любого из форматов
  static Future<void> shareFile(Dish dish, ExportType type) async {
    final tempDir = await getTemporaryDirectory();
    final baseTitle = fileBaseTitle(dish.title);
    final exportsRoot = Directory(p.join(tempDir.path, 'exports'));
    await exportsRoot.create(recursive: true);
    await pruneAbandonedExports(exportsRoot);
    // OS-created unique directory: safe even for equal timestamps and recipe IDs.
    final exportDir = await exportsRoot.createTemp('blank_');

    var handedOff = false;
    try {
      String fileName;
      List<int> bytes;
      String mimeType;

      switch (type) {
        case ExportType.pdf:
          fileName = '${baseTitle}.pdf';
          bytes = await PdfBlankGenerator.generate(dish);
          mimeType = 'application/pdf';
          break;
        case ExportType.docx:
          fileName = '${baseTitle}.docx';
          bytes = DocxBlankGenerator.generate(dish);
          mimeType =
              'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
          break;
        case ExportType.xlsx:
          fileName = '${baseTitle}.xlsx';
          bytes = XlsxBlankGenerator.generate(dish);
          mimeType =
              'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
          break;
      }

      final filePath = p.join(exportDir.path, fileName);
      final file = File(filePath);
      await file.writeAsBytes(bytes, flush: true);

      await Share.shareXFiles(
        [XFile(filePath, mimeType: mimeType, name: fileName)],
        subject: 'Бланк расчёта пищевой ценности: $baseTitle',
      );
      handedOff = true;
    } finally {
      // share_plus 9 Android copies input to its own FileProvider cache before
      // returning. Delete only our staging copy, never the recipient's URI file.
      if (!handedOff || defaultTargetPlatform == TargetPlatform.android) {
        try {
          await exportDir.delete(recursive: true);
        } on FileSystemException {/* next prune retries */}
      }
    }
  }

  /// Пакетный экспорт сборника блюд: единый PDF или книга Excel (.xlsx).
  static Future<void> shareBatchFile(
    List<Dish> dishes,
    ExportType type, {
    DateTime? now,
  }) async {
    if (dishes.isEmpty) {
      throw ArgumentError('Выберите хотя бы одно блюдо для экспорта');
    }
    if (type == ExportType.docx) {
      throw UnsupportedError('Пакетный экспорт поддерживается для PDF и XLSX');
    }

    final dt = now ?? DateTime.now();
    final dateTag = '${dt.year.toString().padLeft(4, '0')}'
        '${dt.month.toString().padLeft(2, '0')}'
        '${dt.day.toString().padLeft(2, '0')}';

    final tempDir = await getTemporaryDirectory();
    final exportsRoot = Directory(p.join(tempDir.path, 'exports'));
    await exportsRoot.create(recursive: true);
    await pruneAbandonedExports(exportsRoot);
    final exportDir = await exportsRoot.createTemp('blank_');

    var handedOff = false;
    try {
      final String fileName;
      final List<int> bytes;
      final String mimeType;
      if (type == ExportType.pdf) {
        fileName = 'Сборник_блюд_$dateTag.pdf';
        bytes = await PdfBlankGenerator.generateBatch(dishes);
        mimeType = 'application/pdf';
      } else {
        fileName = 'Сборник_блюд_$dateTag.xlsx';
        bytes = XlsxBlankGenerator.generateBatch(dishes);
        mimeType =
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
      }

      final filePath = p.join(exportDir.path, fileName);
      final file = File(filePath);
      await file.writeAsBytes(bytes, flush: true);

      await Share.shareXFiles(
        [XFile(filePath, mimeType: mimeType, name: fileName)],
        subject: 'Сборник бланков КБЖУ (${_pluralDishes(dishes.length)})',
      );
      handedOff = true;
    } finally {
      if (!handedOff || defaultTargetPlatform == TargetPlatform.android) {
        try {
          await exportDir.delete(recursive: true);
        } on FileSystemException {/* next prune retries */}
      }
    }
  }

  /// Читаемая текстовая сводка КБЖУ и состава для буфера обмена и мессенджеров.
  static String formatPlainTextSummary(Dish dish, CalculationResult calc) {
    final title = dish.title.trim().isEmpty ? 'Расчёт КБЖУ' : dish.title.trim();
    final m = CalculationEngine.formatMacro;
    final k = CalculationEngine.formatKcal;
    final g = CalculationEngine.formatGrams;

    final buf = StringBuffer()
      ..writeln(title)
      ..writeln('Обработка: ${calc.process.label}')
      ..writeln(
        'На всё блюдо: Б ${m(calc.cookedProtein)} г · '
        'Ж ${m(calc.cookedFat)} г · '
        'У ${m(calc.cookedCarbs)} г · '
        '${k(calc.cookedKcal)} ккал',
      );
    if (calc.hasYield) {
      buf.writeln(
        'На 100 г (выход ${g(calc.yieldGrams)} г): '
        'Б ${m(calc.per100gProtein)} г · '
        'Ж ${m(calc.per100gFat)} г · '
        'У ${m(calc.per100gCarbs)} г · '
        '${k(calc.per100gKcal)} ккал',
      );
    } else if (calc.usesLossTable) {
      buf.writeln('Выход готового блюда не указан');
    }

    if (dish.ingredients.isNotEmpty) {
      buf.writeln('');
      buf.writeln('Состав (${dish.ingredients.length}):');
      for (var i = 0; i < dish.ingredients.length; i++) {
        final ing = dish.ingredients[i];
        final netStr = '${g(ing.netGramsRounded)} г нетто';
        final weightText = ing.isGross && ing.product.wastePct > 0
            ? '${g(ing.weightGrams)} г брутто ($netStr)'
            : '${g(ing.netGramsRounded)} г';
        buf.writeln('${i + 1}. ${ing.product.name} — $weightText');
      }
    }
    return buf.toString().trimRight();
  }
}
