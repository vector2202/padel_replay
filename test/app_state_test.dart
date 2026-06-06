import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:padel_snap/app_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppState Unit Tests', () {
    setUp(() {
      // Initialize SharedPreferences with mock values
      SharedPreferences.setMockInitialValues({});
      // Reset AppState singleton properties to defaults
      AppState().clearSession();
      AppState().setEdgeNodeIp("192.168.0.15");
    });

    test('Default values are correct before initialization', () {
      final appState = AppState();
      expect(appState.edgeNodeIp, equals("192.168.0.15"));
      expect(appState.activeCourt, isNull);
      expect(appState.hasActiveSession, isFalse);
    });

    test('init() loads default edgeNodeIp if SharedPreferences is empty', () async {
      final appState = AppState();
      await appState.init();
      expect(appState.edgeNodeIp, equals("192.168.0.15"));
    });

    test('init() loads custom edgeNodeIp from SharedPreferences', () async {
      SharedPreferences.setMockInitialValues({'edge_node_ip': '192.168.1.100'});
      
      final appState = AppState();
      await appState.init();
      expect(appState.edgeNodeIp, equals("192.168.1.100"));
    });

    test('setEdgeNodeIp() updates IP, notifies listeners, and persists to SharedPreferences', () async {
      final appState = AppState();
      await appState.init();

      var listenerNotified = false;
      appState.addListener(() {
        listenerNotified = true;
      });

      appState.setEdgeNodeIp("192.168.1.50");

      expect(appState.edgeNodeIp, equals("192.168.1.50"));
      expect(listenerNotified, isTrue);

      // Verify persistence by initializing a new SharedPreferences reference
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('edge_node_ip'), equals("192.168.1.50"));
    });

    test('setActiveCourt() starts active session and triggers listener', () {
      final appState = AppState();
      
      var listenerNotified = false;
      appState.addListener(() {
        listenerNotified = true;
      });

      final mockCourt = {
        'id': 'court_123',
        'name': 'Court Central',
        'club': 'Pladel Club'
      };

      appState.setActiveCourt(mockCourt);

      expect(appState.activeCourt, equals(mockCourt));
      expect(appState.hasActiveSession, isTrue);
      expect(listenerNotified, isTrue);
    });

    test('clearSession() removes session and triggers listener', () {
      final appState = AppState();
      
      final mockCourt = {
        'id': 'court_123',
        'name': 'Court Central',
      };
      appState.setActiveCourt(mockCourt);
      expect(appState.hasActiveSession, isTrue);

      var listenerNotified = false;
      appState.addListener(() {
        listenerNotified = true;
      });

      appState.clearSession();

      expect(appState.activeCourt, isNull);
      expect(appState.hasActiveSession, isFalse);
      expect(listenerNotified, isTrue);
    });
  });
}
