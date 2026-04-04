import 'package:flutter_test/flutter_test.dart';
import 'package:nudge/main.dart';  // ← changed from nudge_app to nudge

void main() {
  testWidgets('App launches without crashing', (WidgetTester tester) async {
    await tester.pumpWidget(const StudentTaskApp());
  });
}