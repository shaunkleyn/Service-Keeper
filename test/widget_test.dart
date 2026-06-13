import 'package:flutter_test/flutter_test.dart';
import 'package:service_keeper/main.dart';

void main() {
  testWidgets('App smoke test', (tester) async {
    await tester.pumpWidget(const ServiceKeeperApp());
    expect(find.text('Service Keeper'), findsWidgets);
  });
}
