import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import '../calculation/models/dish.dart';
import 'docx_blank_generator.dart';
import 'pdf_blank_generator.dart';
import 'xlsx_blank_generator.dart';

enum ExportType { pdf, docx, xlsx }

class ExportService {
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
        subject: 'Бланк расчета пищевой ценности: $baseTitle',
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
}
