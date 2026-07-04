import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../app_prefs.dart';
import '../expense_categories.dart';
import '../models/subscription.dart';

/// Exports the user's tracked subscriptions as a CSV file and opens the system
/// share sheet so they can save it to Files, email it, or send it anywhere.
class ExportService {
  // Brand colours for the PDF (const so they can be reused freely).
  static const _green = PdfColor.fromInt(0xFF174E35);
  static const _greenSoft = PdfColor.fromInt(0xFFEDF6F0);
  static const _ink = PdfColor.fromInt(0xFF11231A);
  static const _muted = PdfColor.fromInt(0xFF6B7E74);

  /// Writes a CSV of [subs] to a temp file and shares it. [sharePositionOrigin]
  /// anchors the share popover on iPad (ignored on iPhone).
  static Future<void> shareCsv(
    List<Subscription> subs, {
    required bool isLithuanian,
    Rect? sharePositionOrigin,
  }) async {
    final csv = buildCsv(subs, isLithuanian: isLithuanian);
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/vaultie_export.csv');
    await file.writeAsString(csv, flush: true);
    await SharePlus.instance.share(
      ShareParams(
        files: [
          XFile(file.path, mimeType: 'text/csv', name: 'vaultie_export.csv'),
        ],
        subject: 'Vaultie',
        sharePositionOrigin: sharePositionOrigin,
      ),
    );
  }

  /// The CSV text. Prefixed with a UTF-8 BOM so spreadsheet apps (Excel/Numbers)
  /// detect the encoding and render the € symbol and accented names correctly.
  static String buildCsv(
    List<Subscription> subs, {
    required bool isLithuanian,
  }) {
    final header = isLithuanian
        ? [
            'Pavadinimas',
            'Kategorija',
            'Suma',
            'Valiuta',
            'Ciklas',
            'Kitas mokėjimas',
            'Kaina per mėnesį',
            'Įvertinta',
            'Pastabos',
          ]
        : [
            'Name',
            'Category',
            'Amount',
            'Currency',
            'Cycle',
            'Next payment',
            'Monthly cost',
            'Estimated',
            'Notes',
          ];
    final currency = AppPrefs.currency.value;
    final buf = StringBuffer('﻿');
    buf.writeln(header.map(_escape).join(','));
    for (final s in subs) {
      final row = [
        s.name,
        categoryLabel(normalizeCategoryKey(s.category), isLithuanian),
        s.cost.toStringAsFixed(2),
        currency,
        _cycle(s.billingCycle, isLithuanian),
        _date(s.nextBillingDate),
        s.monthlyCost.toStringAsFixed(2),
        s.isEstimated
            ? (isLithuanian ? 'Taip' : 'Yes')
            : (isLithuanian ? 'Ne' : 'No'),
        s.notes ?? '',
      ];
      buf.writeln(row.map(_escape).join(','));
    }
    return buf.toString();
  }

  // ── PDF report ─────────────────────────────────────────────────────────

  /// Builds a branded PDF report of [subs] and opens the share sheet.
  static Future<void> sharePdf(
    List<Subscription> subs, {
    required bool isLithuanian,
    Rect? sharePositionOrigin,
  }) async {
    final bytes = await buildPdf(subs, isLithuanian: isLithuanian);
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/vaultie_report.pdf');
    await file.writeAsBytes(bytes, flush: true);
    await SharePlus.instance.share(
      ShareParams(
        files: [
          XFile(file.path,
              mimeType: 'application/pdf', name: 'vaultie_report.pdf'),
        ],
        subject: 'Vaultie',
        sharePositionOrigin: sharePositionOrigin,
      ),
    );
  }

  /// A formatted, branded A4 report: logo header, monthly/yearly/count summary,
  /// and a table of every subscription. Uses bundled Lato so Lithuanian
  /// characters and the € symbol render (the built-in PDF fonts don't cover
  /// them).
  static Future<Uint8List> buildPdf(
    List<Subscription> subs, {
    required bool isLithuanian,
  }) async {
    final reg =
        pw.Font.ttf(await rootBundle.load('assets/fonts/Lato-Regular.ttf'));
    final bold =
        pw.Font.ttf(await rootBundle.load('assets/fonts/Lato-Bold.ttf'));
    final logo = pw.MemoryImage(
        (await rootBundle.load('assets/icon/app_icon.png'))
            .buffer
            .asUint8List());
    final theme = pw.ThemeData.withFont(base: reg, bold: bold);

    final monthly = subs.fold<double>(0, (a, s) => a + s.monthlyCost);
    final yearly = monthly * 12;

    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        theme: theme,
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (context) => [
          _pdfHeader(logo, bold, isLithuanian),
          pw.SizedBox(height: 20),
          pw.Row(children: [
            _pdfStat(isLithuanian ? 'Per mėnesį' : 'Monthly',
                formatMoney(monthly), bold),
            pw.SizedBox(width: 12),
            _pdfStat(isLithuanian ? 'Per metus' : 'Yearly', formatMoney(yearly),
                bold),
            pw.SizedBox(width: 12),
            _pdfStat(isLithuanian ? 'Prenumeratos' : 'Subscriptions',
                '${subs.length}', bold),
          ]),
          pw.SizedBox(height: 22),
          pw.TableHelper.fromTextArray(
            border: null,
            headerHeight: 28,
            cellHeight: 26,
            headerStyle:
                pw.TextStyle(font: bold, color: PdfColors.white, fontSize: 10),
            headerDecoration: const pw.BoxDecoration(color: _green),
            cellStyle: const pw.TextStyle(fontSize: 10, color: _ink),
            oddRowDecoration: const pw.BoxDecoration(color: _greenSoft),
            cellAlignments: const {
              4: pw.Alignment.centerRight,
              5: pw.Alignment.centerRight,
            },
            headers: isLithuanian
                ? [
                    'Pavadinimas',
                    'Kategorija',
                    'Ciklas',
                    'Kitas',
                    'Suma',
                    'Per mėn.'
                  ]
                : ['Name', 'Category', 'Cycle', 'Next', 'Amount', 'Monthly'],
            data: [
              for (final s in subs)
                [
                  s.name,
                  categoryLabel(normalizeCategoryKey(s.category), isLithuanian),
                  _cycle(s.billingCycle, isLithuanian),
                  _date(s.nextBillingDate),
                  '${s.isEstimated ? '~' : ''}${formatMoney(s.cost)}',
                  formatMoney(s.monthlyCost),
                ],
            ],
          ),
        ],
        footer: (context) => pw.Padding(
          padding: const pw.EdgeInsets.only(top: 8),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('Vaultie',
                  style: const pw.TextStyle(color: _muted, fontSize: 9)),
              pw.Text('${context.pageNumber} / ${context.pagesCount}',
                  style: const pw.TextStyle(color: _muted, fontSize: 9)),
            ],
          ),
        ),
      ),
    );
    return doc.save();
  }

  static pw.Widget _pdfHeader(pw.MemoryImage logo, pw.Font bold, bool isLt) {
    return pw.Row(
      children: [
        pw.Container(
          width: 46,
          height: 46,
          decoration: pw.BoxDecoration(
            borderRadius: pw.BorderRadius.circular(11),
            image: pw.DecorationImage(image: logo, fit: pw.BoxFit.cover),
          ),
        ),
        pw.SizedBox(width: 12),
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('Vaultie',
                style: pw.TextStyle(font: bold, fontSize: 22, color: _green)),
            pw.Text(isLt ? 'Prenumeratų ataskaita' : 'Subscriptions report',
                style: const pw.TextStyle(color: _muted, fontSize: 11)),
          ],
        ),
        pw.Spacer(),
        pw.Text(_today(isLt),
            style: const pw.TextStyle(color: _muted, fontSize: 10)),
      ],
    );
  }

  static pw.Widget _pdfStat(String label, String value, pw.Font bold) {
    return pw.Expanded(
      child: pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: pw.BoxDecoration(
          color: _greenSoft,
          borderRadius: pw.BorderRadius.circular(10),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(label.toUpperCase(),
                style: const pw.TextStyle(
                    color: _muted, fontSize: 8, letterSpacing: 0.5)),
            pw.SizedBox(height: 4),
            pw.Text(value,
                style: pw.TextStyle(font: bold, fontSize: 16, color: _green)),
          ],
        ),
      ),
    );
  }

  static String _today(bool isLt) {
    final d = DateTime.now();
    return '${isLt ? 'Sukurta' : 'Generated'} ${_date(d)}';
  }

  /// RFC-4180 field quoting: wrap in quotes and double any embedded quotes when
  /// the value contains a comma, quote, or newline.
  static String _escape(String v) {
    if (v.contains(',') ||
        v.contains('"') ||
        v.contains('\n') ||
        v.contains('\r')) {
      return '"${v.replaceAll('"', '""')}"';
    }
    return v;
  }

  static String _date(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  static String _cycle(BillingCycle c, bool isLt) => switch (c) {
        BillingCycle.weekly => isLt ? 'Savaitinis' : 'Weekly',
        BillingCycle.monthly => isLt ? 'Mėnesinis' : 'Monthly',
        BillingCycle.quarterly => isLt ? 'Ketvirtinis' : 'Quarterly',
        BillingCycle.yearly => isLt ? 'Metinis' : 'Yearly',
      };
}
