import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:atlas_mobile/features/student_dashboard/student_dashboard_screen.dart';

void main() {
  testWidgets('student dashboard hides the analytics tab', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: StudentDashboardScreen()));
    await tester.pump();

    expect(find.text('Dashboard'), findsOneWidget);
    expect(find.text('Analytics'), findsNothing);
  });
}
