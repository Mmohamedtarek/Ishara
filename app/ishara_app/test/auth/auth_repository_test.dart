import 'package:flutter_test/flutter_test.dart';
import 'package:ishara_app/core/auth/auth_repository.dart';

Matcher _fails(AuthProblem p) =>
    throwsA(isA<AuthFailure>().having((f) => f.problem, 'problem', p));

void main() {
  late FakeAuthRepository repo;
  setUp(() => repo = FakeAuthRepository(delay: Duration.zero));
  tearDown(() => repo.dispose());

  test('create account, sign out, sign in again', () async {
    final events = <AuthUser?>[];
    final sub = repo.userChanges.listen(events.add);
    final u = await repo.createAccount(
      name: ' Mona ',
      email: ' Mona@Example.com ',
      password: 'secret123',
    );
    expect(u.email, 'mona@example.com');
    expect(u.name, 'Mona');
    expect(u.emailVerified, isFalse);
    expect(repo.currentUser, u);
    await repo.signOut();
    expect(repo.currentUser, isNull);
    final again = await repo.signIn(
      email: 'mona@example.com',
      password: 'secret123',
    );
    expect(again.id, u.id);
    await Future<void>.delayed(Duration.zero);
    expect(events.map((e) => e?.email), [
      'mona@example.com',
      null,
      'mona@example.com',
    ]);
    await sub.cancel();
  });

  test('wrong password and unknown email give the same answer', () async {
    await repo.createAccount(name: 'A', email: 'a@b.co', password: '12345678');
    await repo.signOut();
    expect(
      repo.signIn(email: 'a@b.co', password: 'nope-nope'),
      _fails(AuthProblem.invalidCredentials),
    );
    expect(
      repo.signIn(email: 'x@b.co', password: '12345678'),
      _fails(AuthProblem.invalidCredentials),
    );
  });

  test('an email can have only one account', () async {
    await repo.createAccount(name: 'A', email: 'a@b.co', password: '12345678');
    expect(
      repo.createAccount(name: 'B', email: 'A@B.CO', password: '87654321'),
      _fails(AuthProblem.emailInUse),
    );
  });

  test('offline, and a scripted failure for the next call', () async {
    repo.offline = true;
    expect(
      repo.signIn(email: 'a@b.co', password: '12345678'),
      _fails(AuthProblem.network),
    );
    expect(repo.sendPasswordReset('a@b.co'), _fails(AuthProblem.network));
    repo
      ..offline = false
      ..failNext = AuthProblem.tooManyRequests;
    expect(
      repo.signIn(email: 'a@b.co', password: '12345678'),
      _fails(AuthProblem.tooManyRequests),
    );
  });

  test('password reset succeeds for any email (no account leak)', () async {
    await repo.sendPasswordReset(' Who@Ever.com ');
    expect(repo.resetsSent, ['who@ever.com']);
  });

  test('form checks (prototype rules, email only)', () {
    expect(AuthValidation.nameMissing('  '), isTrue);
    expect(AuthValidation.nameMissing('Ali'), isFalse);
    expect(AuthValidation.emailMissing(''), isTrue);
    for (final bad in ['a', 'a@b', '@b.co', 'a b@c.d', '01012345678']) {
      expect(AuthValidation.emailMalformed(bad), isTrue, reason: bad);
    }
    expect(AuthValidation.emailMalformed(' you@example.com '), isFalse);
    expect(AuthValidation.passwordTooShort('1234567'), isTrue);
    expect(AuthValidation.passwordTooShort('12345678'), isFalse);
  });
}
