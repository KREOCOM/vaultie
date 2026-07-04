import 'package:flutter_test/flutter_test.dart';
import 'package:vaultie/models/subscription.dart';
import 'package:vaultie/services/export_service.dart';

Subscription _sub(String name, {String? notes, double cost = 9.99}) => Subscription(
      id: 'x',
      name: name,
      cost: cost,
      billingCycle: BillingCycle.monthly,
      category: 'other',
      nextBillingDate: DateTime(2026, 1, 15),
      notes: notes,
    );

void main() {
  group('ExportService.buildCsv', () {
    test('starts with a UTF-8 BOM, a header, and one row per subscription', () {
      final csv = ExportService.buildCsv(
        [_sub('Netflix'), _sub('Spotify')],
        isLithuanian: false,
      );
      expect(csv.codeUnitAt(0), 0xFEFF); // BOM so Excel reads € / accents
      final lines = csv.trimRight().split('\n');
      expect(lines.length, 3); // header + 2 rows
      expect(lines.first, contains('Name'));
      expect(lines.first, contains('Monthly cost'));
      expect(lines[1], contains('Netflix'));
      expect(lines[2], contains('Spotify'));
    });

    test('quotes fields containing commas and escapes embedded quotes', () {
      final csv = ExportService.buildCsv(
        [_sub('Rent, downtown', notes: 'has "quotes"')],
        isLithuanian: false,
      );
      expect(csv, contains('"Rent, downtown"')); // comma → whole field quoted
      expect(csv, contains('"has ""quotes"""')); // quotes doubled
    });

    test('localizes the header for Lithuanian', () {
      final csv = ExportService.buildCsv([_sub('Netflix')], isLithuanian: true);
      expect(csv, contains('Pavadinimas'));
      expect(csv, contains('Kaina per mėnesį'));
    });
  });
}
