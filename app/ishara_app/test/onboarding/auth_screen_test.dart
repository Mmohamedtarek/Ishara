import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ishara_app/features/onboarding/presentation/auth_screen.dart';

import '../support/screen_harness.dart';

void main() {
  testWidgets('email only (Q-B2): no phone, Google or Remember me', (t) async {
    await pumpScreen(t, const AuthScreen(signUp: true));
    expect(find.text('Create your account'), findsOneWidget);
    expect(find.text('Email'), findsOneWidget);
    expect(find.text('Your name'), findsOneWidget);
    expect(find.textContaining('Google'), findsNothing);
    expect(find.textContaining('phone number'), findsNothing);
    expect(find.text('Remember me'), findsNothing);
  });

  testWidgets('field checks: name, email, password; first bad field focused', (
    t,
  ) async {
    await pumpScreen(t, const AuthScreen(signUp: true));
    await tapIt(t, find.byKey(const ValueKey('auth-submit')));
    expect(find.text('Enter your name'), findsOneWidget);
    expect(find.text('Enter your email'), findsOneWidget);
    expect(find.text('Password must be at least 8 characters'), findsOneWidget);
    final name = t.widget<TextField>(field('auth-name'));
    expect(name.focusNode!.hasFocus, isTrue);
    await t.enterText(field('auth-email'), 'not-an-email');
    await t.pump();
    expect(find.text('Enter your email'), findsNothing, reason: 'clears');
    await tapIt(t, find.byKey(const ValueKey('auth-submit')));
    expect(find.text('Enter a valid email address'), findsOneWidget);
  });

  testWidgets('create account → toast → Setup', (t) async {
    final h = await pumpScreen(t, const AuthScreen(signUp: true));
    await t.enterText(field('auth-name'), 'Mona');
    await t.enterText(field('auth-email'), 'mona@example.com');
    await t.enterText(field('auth-password'), 'secret123');
    await tapIt(t, find.byKey(const ValueKey('auth-submit')));
    expect(h.auth.currentUser?.email, 'mona@example.com');
    expect(find.text('Account created'), findsOneWidget);
    expect(find.text('route:/setup'), findsOneWidget);
    await t.pump(const Duration(seconds: 3)); // the toast goes away
  });

  testWidgets('sign in: wrong password shows one message', (t) async {
    final h = Harness();
    await h.auth.createAccount(
      name: 'A',
      email: 'a@b.co',
      password: '12345678',
    );
    await h.auth.signOut();
    await pumpScreen(t, const AuthScreen(signUp: false), harness: h);
    expect(find.text('Welcome back'), findsOneWidget);
    await t.enterText(field('auth-email'), 'a@b.co');
    await t.enterText(field('auth-password'), 'wrong-pass');
    await tapIt(t, find.byKey(const ValueKey('auth-submit')));
    expect(find.text('Wrong email or password.'), findsOneWidget);
    expect(h.auth.currentUser, isNull);
  });

  testWidgets('offline', (t) async {
    final h = Harness()..auth.offline = true;
    await pumpScreen(t, const AuthScreen(signUp: false), harness: h);
    await t.enterText(field('auth-email'), 'a@b.co');
    await t.enterText(field('auth-password'), '12345678');
    await tapIt(t, find.byKey(const ValueKey('auth-submit')));
    expect(
      find.text('No internet connection. Check it and try again.'),
      findsOneWidget,
    );
  });

  testWidgets('forgot password needs an email; then sends the link', (t) async {
    final h = await pumpScreen(t, const AuthScreen(signUp: false));
    await tapIt(t, find.byKey(const ValueKey('auth-forgot')));
    expect(
      find.text('Enter your email above first, then tap Forgot password.'),
      findsOneWidget,
    );
    await t.enterText(field('auth-email'), 'a@b.co');
    await tapIt(t, find.byKey(const ValueKey('auth-forgot')));
    expect(h.auth.resetsSent, ['a@b.co']);
    expect(find.text('Reset link sent'), findsOneWidget);
    await t.pump(const Duration(seconds: 3));
  });

  testWidgets('show / hide password; switch mode; guest', (t) async {
    await pumpScreen(t, const AuthScreen(signUp: false));
    TextField pw() => t.widget<TextField>(field('auth-password'));
    expect(pw().obscureText, isTrue);
    await tapIt(t, find.byKey(const ValueKey('auth-eye')));
    expect(pw().obscureText, isFalse);
    await tapIt(t, find.byKey(const ValueKey('auth-seg-signup')));
    expect(find.text('Create your account'), findsOneWidget);
    await tapIt(t, find.byKey(const ValueKey('auth-guest')));
    expect(find.text('route:/setup'), findsOneWidget);
  });
}
