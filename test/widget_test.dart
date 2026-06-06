import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:padel_snap/login_screen.dart';

void main() {
  testWidgets('LoginScreen toggles between Sign In and Sign Up modes', (WidgetTester tester) async {
    // Render the LoginScreen inside a MaterialApp
    await tester.pumpWidget(
      const MaterialApp(
        home: LoginScreen(),
      ),
    );

    // 1. Verify standard Sign In UI elements
    expect(find.text('PADEL\nSNAP'), findsOneWidget);
    expect(find.text('Email'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
    expect(find.text('ENTRAR'), findsOneWidget);
    
    // Verify that 'Username' field does NOT exist in Login mode
    expect(find.text('Username'), findsNothing);

    // 2. Toggle to Sign Up mode
    final toggleButton = find.text('¿No tienes cuenta? Regístrate');
    expect(toggleButton, findsOneWidget);
    await tester.tap(toggleButton);
    await tester.pump(); // trigger transition frame

    // 3. Verify Sign Up UI elements are now active
    expect(find.text('Username'), findsOneWidget);
    expect(find.text('CREAR CUENTA'), findsOneWidget);
    
    // Verify the toggle text has changed
    expect(find.text('¿Ya tienes cuenta? Entra aquí'), findsOneWidget);

    // 4. Toggle back to Sign In mode
    final toggleBack = find.text('¿Ya tienes cuenta? Entra aquí');
    await tester.tap(toggleBack);
    await tester.pump();

    // Verify it returned to Sign In mode
    expect(find.text('Username'), findsNothing);
    expect(find.text('ENTRAR'), findsOneWidget);
  });
}

