import 'dart:io';
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
  /// Прямая печать или встроенный просмотр PDF на Android
  static Future<void> printPdf(Dish dish) async {
    final pdfBytes = await PdfBlankGenerator.generate(dish);
    final title = dish.title.isNotEmpty ? dish.title : 'Бланк_расчета';
    await Printing.layoutPdf(
      onLayout: (format) async => pdfBytes,
      name: '${title}.pdf',
    );
  }

  /// Экспорт и открытие системного диалога "Поделиться" для любого из форматов
  static Future<void> shareFile(Dish dish, ExportType type) async {
    final tempDir = await getTemporaryDirectory();
    final baseTitle = dish.title.isNotEmpty
        ? dish.title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
        : 'Бланк_расчета';

    final exportId =
        '${DateTime.now().microsecondsSinceEpoch}_${dish.id.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')}';
    final exportDir = Directory(p.join(tempDir.path, 'exports', exportId));
    await exportDir.create(recursive: true);

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
  }
}
