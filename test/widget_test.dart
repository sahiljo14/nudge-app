import 'package:flutter_test/flutter_test.dart';
import 'package:nudge_app/main.dart';

void main() {
  testWidgets('App launches without crashing', (WidgetTester tester) async {
    await tester.pumpWidget(const StudentTaskApp());
  });
}