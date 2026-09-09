import 'package:flutter_test/flutter_test.dart';
import 'package:service_keeper/main.dart';

void main() {
  testWidgets('App smoke test', (tester) async {
    await tester.pumpWidget(const ServiceKeeperApp());
    expect(find.text('Service Keeper'), findsWidgets);
    // Splash screen's Future.delayed chain totals ~1990ms; flush it (with
    // headroom) so no timers are left pending when the test ends.
    await tester.pump(const Duration(seconds: 3));
  });
}
