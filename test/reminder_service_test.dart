import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:ultron_mobile/services/reminder_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  test('reschedulePendingAlarms re-schedules only future PENDING reminders',
      () async {
    const channel = MethodChannel('com.viniciusnpaula.ultron_mobile/device_test');
    final scheduledCalls = <Map<Object?, Object?>>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'scheduleReminderAlarm') {
        scheduledCalls.add(Map<Object?, Object?>.from(call.arguments as Map));
        return true;
      }
      if (call.method == 'cancelReminderAlarm') {
        return true;
      }
      return null;
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    final svc = await ReminderService.open(database: db, channel: channel);
    addTearDown(svc.close);

    final now = DateTime(2026, 11, 23, 12, 0);
    // Past reminder (should not be rescheduled)
    await svc.createReminder(
      title: 'Lembrete vencido',
      scheduledAt: now.subtract(const Duration(hours: 2)),
      now: now,
    );
    // Future warranty reminder (months ahead)
    final warranty = await svc.createReminder(
      title: 'Garantia Monitor LG vence em 15 dias',
      scheduledAt: DateTime(2027, 11, 8, 9, 0),
      now: now,
    );
    // Cancelled future reminder (should not be rescheduled)
    final cancelled = await svc.createReminder(
      title: 'Lembrete cancelado',
      scheduledAt: now.add(const Duration(days: 10)),
      now: now,
    );
    await svc.cancelReminder('${cancelled.id}');

    scheduledCalls.clear();
    final count = await svc.reschedulePendingAlarms(now: now);
    expect(count, 1);
    expect(scheduledCalls.length, 1);
    expect(scheduledCalls.first['id'], warranty.id);
    expect(scheduledCalls.first['title'], 'Garantia Monitor LG vence em 15 dias');
  });
}
