import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pake_shell/src/update/pending_update.dart';
import 'package:pake_shell/src/update/update_check.dart';

const _info = UpdateInfo(
  version: '1.2.0',
  tag: 'fourkvm-v1.2.0',
  downloadUrl: 'https://dl/app.apk',
);

void main() {
  late ValueNotifier<bool> locked;
  late List<UpdateInfo> shown;
  late PendingUpdate pending;

  setUp(() {
    locked = ValueNotifier(false);
    shown = [];
    pending = PendingUpdate(locked: locked, onReady: shown.add);
  });

  tearDown(() {
    pending.dispose();
    locked.dispose();
  });

  test('shows right away when nothing is covering the screen', () {
    pending.offer(_info);

    expect(shown, [_info]);
  });

  // 锁着的时候弹 = 被锁屏盖住，用户看不见，而「每个版本只弹一次」已经用掉了。
  test('holds it back while the lock screen is up', () {
    locked.value = true;
    pending.offer(_info);

    expect(shown, isEmpty);

    locked.value = false;
    expect(shown, [_info]);
  });

  test('shows it once, not once per notification', () {
    locked.value = true;
    pending.offer(_info);

    locked
      ..value = false
      ..notifyListeners()
      ..value = true
      ..value = false;

    expect(shown, [_info]);
  });

  test('stops listening after dispose', () {
    locked.value = true;
    pending.offer(_info);
    pending.dispose();

    locked.value = false;
    expect(shown, isEmpty);
  });
}
