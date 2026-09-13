import 'package:flutter_test/flutter_test.dart';
import 'package:nus_gamepad_companion/data/repositories/ble_repository.dart';
import 'package:nus_gamepad_companion/ui/features/scan/view_models/scan_view_model.dart';
import 'package:nus_gamepad_companion/ui/features/terminal/view_models/terminal_view_model.dart';

void main() {
  group('BleRepository invariants', () {
    late BleRepository repo;

    setUp(() {
      repo = BleRepository();
    });

    tearDown(() {
      repo.dispose();
    });

    test('initial state is idle and empty log', () {
      expect(repo.state, NusConnState.idle);
      expect(repo.log, isEmpty);
      expect(repo.activeProfileId, isNull);
      expect(repo.clearLogOnConnect, isTrue);
      expect(repo.showTimestamps, isFalse);
    });

    test('setProfileOverride updates activeProfileId and logs', () {
      repo.setProfileOverride('nus-bridge/xinput');
      expect(repo.activeProfileId, 'nus-bridge/xinput');
      expect(repo.log.last.message.display, contains('xinput'));
    });

    test('rumbleVibrateMs delegation via facade matches repository', () {
      // BleRepository owns the pure function; facade delegates.
      expect(BleRepository.rumbleVibrateMs('left=255'), 250);
      expect(BleRepository.rumbleVibrateMs('ltrig=99'), 0);
    });

    test('clearLog empties terminal', () {
      repo.setProfileOverride('generic');
      expect(repo.log, isNotEmpty);
      repo.clearLog();
      expect(repo.log, isEmpty);
    });

    test('preference toggles persist in-memory', () {
      repo.setClearLogOnConnect(false);
      expect(repo.clearLogOnConnect, isFalse);
      repo.setShowTimestamps(true);
      expect(repo.showTimestamps, isTrue);
      repo.setVibrateOnRumble(true);
      expect(repo.vibrateOnRumble, isTrue);
    });
  });

  group('ScanViewModel', () {
    late BleRepository repo;
    late ScanViewModel vm;

    setUp(() {
      repo = BleRepository();
      vm = ScanViewModel(repository: repo);
    });

    tearDown(() {
      vm.dispose();
      repo.dispose();
    });

    test('initial filter is NuS and showAll false', () {
      expect(vm.filter, 'NuS');
      expect(vm.showAll, isFalse);
      expect(vm.scanning, isFalse);
    });

    test('setFilter notifies and updates', () {
      var notified = false;
      vm.addListener(() => notified = true);
      vm.setFilter('ESp');
      expect(vm.filter, 'ESp');
      expect(notified, isTrue);
    });

    test('setShowAll toggles', () {
      vm.setShowAll(true);
      expect(vm.showAll, isTrue);
    });

    test('adapterState delegates to repository', () {
      expect(vm.adapterState, isNotNull);
    });

    test('propagates repository errorText changes', () {
      repo.errorText = 'boom';
      // ViewModel listens to repo and notifies.
      // Pump one microtask to allow notification.
      expect(vm.errorText, 'boom');
    });
  });

  group('TerminalViewModel', () {
    late BleRepository repo;
    late TerminalViewModel vm;

    setUp(() {
      repo = BleRepository();
      vm = TerminalViewModel(repository: repo);
    });

    tearDown(() {
      vm.dispose();
      repo.dispose();
    });

    test('exposes repository log and profile', () {
      repo.setProfileOverride('nus-diag');
      expect(vm.activeProfileId, 'nus-diag');
      expect(vm.log.last.message.display, contains('nus-diag'));
    });

    test('sendLine is no-op when not ready (preserves MTU invariant)', () async {
      // Not connected => sendLine should complete without throwing
      // and without adding outgoing entry.
      final before = vm.log.length;
      await vm.sendLine('help');
      expect(vm.log.length, before);
    });

    test('clearLog delegates', () {
      repo.setProfileOverride('generic');
      vm.clearLog();
      expect(vm.log, isEmpty);
    });

    test('host status delegates', () {
      repo.lastLedIndex = 2;
      expect(vm.lastLedIndex, 2);
      repo.lastRgb = [10, 20, 30];
      expect(vm.lastRgb, [10, 20, 30]);
    });
  });
}
