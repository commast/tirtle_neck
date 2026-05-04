import 'package:flutter_test/flutter_test.dart';
import 'package:tirtle_ml/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const TirtleApp());
    expect(find.byType(TirtleApp), findsOneWidget);
  });
}
