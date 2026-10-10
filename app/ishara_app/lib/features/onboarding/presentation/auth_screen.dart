import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ishara_app/core/auth/auth_providers.dart';
import 'package:ishara_app/core/auth/auth_repository.dart';
import 'package:ishara_app/core/router/app_routes.dart';
import 'package:ishara_app/core/theme/ishara_theme.dart';
import 'package:ishara_app/core/ui/ishara_icon.dart';
import 'package:ishara_app/core/ui/onboarding_ui.dart';
import 'package:ishara_app/core/ui/toast.dart';
import 'package:ishara_app/l10n/gen/app_localizations.dart';

/// Prototype `#s-login`, email + password only (Q-B2): sign in or create an
/// account on the [AuthRepository] (the local fake until Firebase, S6-1), or
/// continue as a guest.
class AuthScreen extends ConsumerStatefulWidget {
  const new({required this.signUp, super.key});

  /// Opened from "Get started" (create) or "I already have an account".
  final bool signUp;

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

enum _Field { name, email, password }

class _AuthScreenState extends ConsumerState<AuthScreen> {
  late bool _signUp = widget.signUp;
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final Map<_Field, FocusNode> _focus = {
    for (final f in _Field.values) f: FocusNode(),
  };
  final _errors = <_Field, String>{};
  bool _showPassword = false;
  bool _busy = false;
  String? _formError;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    for (final f in _focus.values) {
      f.dispose();
    }
    super.dispose();
  }

  void _setMode({required bool signUp}) => setState(() {
    _signUp = signUp;
    _errors.clear();
    _formError = null;
  });

  String _problemText(AppLocalizations l, AuthProblem p) => switch (p) {
    AuthProblem.invalidCredentials => l.authErrInvalid,
    AuthProblem.emailInUse => l.authErrEmailInUse,
    AuthProblem.network => l.authErrNetwork,
    AuthProblem.tooManyRequests => l.authErrTooMany,
    AuthProblem.unknown => l.authErrUnknown,
  };

  /// Prototype submit handler (email only): name (create), email present and
  /// well formed, password at least 8 characters; focus the first bad field.
  Future<void> _submit() async {
    final l = AppLocalizations.of(context);
    final errors = <_Field, String>{
      if (_signUp && AuthValidation.nameMissing(_name.text))
        _Field.name: l.errName,
      if (AuthValidation.emailMissing(_email.text))
        _Field.email: l.errEmail
      else if (AuthValidation.emailMalformed(_email.text))
        _Field.email: l.errEmailFormat,
      if (AuthValidation.passwordTooShort(_password.text))
        _Field.password: l.errPw,
    };
    setState(() {
      _errors
        ..clear()
        ..addAll(errors);
      _formError = null;
    });
    if (errors.isNotEmpty) {
      _focus[errors.keys.first]!.requestFocus();
      return;
    }
    setState(() => _busy = true);
    final repo = ref.read(authRepositoryProvider);
    try {
      if (_signUp) {
        await repo.createAccount(
          name: _name.text,
          email: _email.text,
          password: _password.text,
        );
      } else {
        await repo.signIn(email: _email.text, password: _password.text);
      }
    } on AuthFailure catch (f) {
      if (mounted) {
        setState(() {
          _busy = false;
          _formError = _problemText(l, f.problem);
        });
      }
      return;
    }
    if (!mounted) return;
    setState(() => _busy = false);
    showToast(context, _signUp ? l.toastCreated : l.toastSignedIn);
    await context.push(AppRoutes.setup);
  }

  Future<void> _forgot() async {
    final l = AppLocalizations.of(context);
    if (AuthValidation.emailMissing(_email.text) ||
        AuthValidation.emailMalformed(_email.text)) {
      setState(
        () => _errors[_Field.email] = AuthValidation.emailMissing(_email.text)
            ? l.forgotNeedsEmail
            : l.errEmailFormat,
      );
      _focus[_Field.email]!.requestFocus();
      return;
    }
    try {
      await ref.read(authRepositoryProvider).sendPasswordReset(_email.text);
    } on AuthFailure catch (f) {
      if (mounted) setState(() => _formError = _problemText(l, f.problem));
      return;
    }
    if (mounted) showToast(context, l.toastForgot);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = context.colors;
    final t = context.text;
    return OnboardingPage(
      screenKey: 'auth',
      top: const OnboardingTopBar(back: true, brand: true),
      body: [
        PageTitle(
          _signUp ? l.createTitle : l.welcomeBack,
          lead: _signUp ? l.createLead : l.loginLeadEmail,
        ),
        _Segmented(
          signUp: _signUp,
          onChanged: (v) => _setMode(signUp: v),
        ),
        AutofillGroup(
          child: Column(
            children: [
              if (_signUp)
                _InputField(
                  key: const ValueKey('auth-name'),
                  label: l.lblName,
                  hint: l.phName,
                  icon: 'user',
                  controller: _name,
                  focus: _focus[_Field.name]!,
                  error: _errors[_Field.name],
                  autofill: const [AutofillHints.name],
                  action: TextInputAction.next,
                  onChanged: () => _clear(_Field.name),
                ),
              _InputField(
                key: const ValueKey('auth-email'),
                label: l.lblEmail,
                hint: l.phEmail,
                icon: 'mail',
                controller: _email,
                focus: _focus[_Field.email]!,
                error: _errors[_Field.email],
                keyboard: TextInputType.emailAddress,
                autofill: const [AutofillHints.email, AutofillHints.username],
                action: TextInputAction.next,
                onChanged: () => _clear(_Field.email),
              ),
              _InputField(
                key: const ValueKey('auth-password'),
                label: l.lblPw,
                hint: l.phPw,
                icon: 'lock',
                controller: _password,
                focus: _focus[_Field.password]!,
                error: _errors[_Field.password],
                obscure: !_showPassword,
                autofill: [
                  if (_signUp)
                    AutofillHints.newPassword
                  else
                    AutofillHints.password,
                ],
                action: TextInputAction.done,
                onSubmitted: _busy ? null : _submit,
                onChanged: () => _clear(_Field.password),
                trailing: _EyeButton(
                  shown: _showPassword,
                  label: _showPassword ? l.hide : l.show,
                  onPressed: () =>
                      setState(() => _showPassword = !_showPassword),
                ),
              ),
            ],
          ),
        ),
        // .remember (Remember me is gone with Q-B2): Forgot password
        Padding(
          padding: const EdgeInsets.only(top: 2, bottom: 14),
          child: Align(
            alignment: AlignmentDirectional.centerEnd,
            child: IsharaLink(
              key: const ValueKey('auth-forgot'),
              label: l.forgot,
              onPressed: _busy ? null : _forgot,
            ),
          ),
        ),
        if (_formError case final e?)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Semantics(
              liveRegion: true,
              child: Text(
                e,
                key: const ValueKey('auth-error'),
                style: t.rowSubtitle.copyWith(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: c.danger,
                ),
              ),
            ),
          ),
        IsharaButton(
          key: const ValueKey('auth-submit'),
          label: _signUp ? l.createAccount : l.signIn,
          arrow: true,
          busy: _busy,
          onPressed: _busy ? null : _submit,
        ),
        _GuestCard(onTap: () => context.push(AppRoutes.setup)),
        Padding(
          padding: const EdgeInsets.only(top: 14),
          child: Text(
            l.termsLocal,
            textAlign: TextAlign.center,
            style: t.rowSubtitle.copyWith(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              height: 1.5,
              color: c.muted,
            ),
          ),
        ),
      ],
    );
  }

  void _clear(_Field f) {
    if (_errors.containsKey(f) || _formError != null) {
      setState(() {
        _errors.remove(f);
        _formError = null;
      });
    }
  }
}

/// `.seg` (radius 16, padding 4; buttons 42 px, radius 12).
class _Segmented extends StatelessWidget {
  const new({required this.signUp, required this.onChanged});

  final bool signUp;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = context.colors;
    final dark = Theme.of(context).brightness == Brightness.dark;
    Widget button(String text, {required bool on, required bool value}) =>
        Expanded(
          child: Semantics(
            selected: on,
            button: true,
            inMutuallyExclusiveGroup: true,
            child: GestureDetector(
              key: ValueKey('auth-seg-${value ? 'signup' : 'signin'}'),
              behavior: HitTestBehavior.opaque,
              onTap: () => onChanged(value),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  gradient: on
                      ? LinearGradient(
                          colors: dark
                              ? const [Color(0x598E9CFF), Color(0x596F7CF0)]
                              : const [Color(0x2E3446C9), Color(0x2E24309A)],
                        )
                      : null,
                ),
                child: Text(
                  text,
                  style: context.text.chip.copyWith(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    color: on ? c.ink : c.muted,
                  ),
                ),
              ),
            ),
          ),
        );
    return Container(
      margin: const EdgeInsets.only(top: 6, bottom: 14),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: c.glass,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.line),
      ),
      child: Row(
        children: [
          button(l.signIn, on: !signUp, value: false),
          button(l.createAccount, on: signUp, value: true),
        ],
      ),
    );
  }
}

/// `.field`: label, a 52 px input row with an icon, and the error
/// (`role=alert`: announced).
class _InputField extends StatelessWidget {
  const new({
    required this.label,
    required this.hint,
    required this.icon,
    required this.controller,
    required this.focus,
    required this.onChanged,
    this.error,
    this.obscure = false,
    this.keyboard,
    this.autofill,
    this.action,
    this.onSubmitted,
    this.trailing,
    super.key,
  });

  final String label;
  final String hint;
  final String icon;
  final TextEditingController controller;
  final FocusNode focus;
  final VoidCallback onChanged;
  final String? error;
  final bool obscure;
  final TextInputType? keyboard;
  final Iterable<String>? autofill;
  final TextInputAction? action;
  final VoidCallback? onSubmitted;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.text;
    final bad = error != null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: t.rowSubtitle.copyWith(
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              color: c.sub,
            ),
          ),
          const SizedBox(height: 6),
          ListenableBuilder(
            listenable: focus,
            builder: (context, child) => AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              height: 52,
              padding: const EdgeInsetsDirectional.only(start: 14, end: 6),
              decoration: BoxDecoration(
                color: c.input,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: bad
                      ? c.danger
                      : focus.hasFocus
                      ? const Color(0xB3B7C0FF)
                      : c.line,
                ),
                boxShadow: bad
                    ? const [
                        BoxShadow(color: Color(0x1FC62B33), spreadRadius: 3),
                      ]
                    : focus.hasFocus
                    ? const [
                        BoxShadow(color: Color(0x268E9CFF), spreadRadius: 3),
                      ]
                    : null,
              ),
              child: child,
            ),
            child: Row(
              children: [
                IsharaIcon(icon, size: 18, color: c.muted),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: controller,
                    focusNode: focus,
                    obscureText: obscure,
                    keyboardType: keyboard,
                    autofillHints: autofill,
                    textInputAction: action,
                    autocorrect: false,
                    enableSuggestions: !obscure,
                    onChanged: (_) => onChanged(),
                    onSubmitted: onSubmitted == null
                        ? null
                        : (_) => onSubmitted!(),
                    style: t.rowTitle.copyWith(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: c.ink,
                    ),
                    cursorColor: c.tealSoft,
                    decoration:
                        InputDecoration.collapsed(
                          hintText: hint,
                          hintStyle: t.rowTitle.copyWith(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: c.muted,
                          ),
                        ).copyWith(
                          // the label above names the field for screen readers
                          semanticCounterText: '',
                        ),
                  ),
                ),
                ?trailing,
              ],
            ),
          ),
          if (error case final e?)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Semantics(
                liveRegion: true,
                child: Text(
                  e,
                  style: t.rowSubtitle.copyWith(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: c.danger,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The show / hide password button (40 px, `aria-pressed`).
class _EyeButton extends StatelessWidget {
  const new({
    required this.shown,
    required this.label,
    required this.onPressed,
  });

  final bool shown;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    toggled: shown,
    label: label,
    excludeSemantics: true,
    child: IconButton(
      key: const ValueKey('auth-eye'),
      onPressed: onPressed,
      iconSize: 18,
      constraints: const BoxConstraints.tightFor(width: 44, height: 44),
      icon: IsharaIcon('eye', size: 18, color: context.colors.muted),
    ),
  );
}

/// `.guest`: dashed amber card, "Continue as guest" and what that means.
class _GuestCard extends StatelessWidget {
  const new({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = context.colors;
    final t = context.text;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Semantics(
        button: true,
        label: '${l.guestTitle}. ${l.guestSub}',
        excludeSemantics: true,
        onTap: onTap,
        child: Material(
          color: dark ? const Color(0x14F2A33A) : const Color(0x0FF2A33A),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(
              color: dark ? const Color(0x73FACD8C) : const Color(0x66F2A33A),
            ),
          ),
          child: InkWell(
            key: const ValueKey('auth-guest'),
            borderRadius: BorderRadius.circular(18),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  const IconTile(
                    icon: 'guest',
                    tone: 'amber',
                    size: 40,
                    iconSize: 20,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l.guestTitle,
                          style: t.rowTitle.copyWith(color: c.ink),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          l.guestSub,
                          style: t.rowSubtitle.copyWith(color: c.muted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
