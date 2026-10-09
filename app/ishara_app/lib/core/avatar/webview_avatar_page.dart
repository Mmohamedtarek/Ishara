import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:ishara_app/core/avatar/avatar_asset_server.dart';
import 'package:ishara_app/core/avatar/avatar_controller.dart';
import 'package:ishara_app/core/logging/log.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// An [AvatarPage] that also has a view to put on screen.
abstract interface class AvatarSurface implements AvatarPage {
  /// The page's view. Built by exactly one place at a time (the avatar slot
  /// that owns it, or the parking spot), under one global key, so the same
  /// native view moves between screens instead of being recreated.
  Widget buildView();

  Future<void> dispose();
}

/// The JavaScript that hands [command] to the page. JSON is a JS literal,
/// so nothing in [command] can break out of the call.
String avatarCommandScript(Map<String, Object?> command) =>
    'window.__ishara && window.__ishara.receive(${jsonEncode(command)});';

/// The avatar page in a WebView, loaded from [AvatarAssetServer].
///
/// The WebView may only show this server's pages: every other navigation is
/// refused, and the page's CSP allows no network at all.
class WebViewAvatarPage implements AvatarSurface {
  new(this._server, {WebViewController? controller})
    : webView = controller ?? WebViewController() {
    unawaited(_setUp());
  }

  static final _log = Log('avatar_page');
  static const _blank = 'about:blank';

  /// The channel the page posts to (engine.js `post`).
  static const channel = 'IsharaBridge';

  final AvatarAssetServer _server;
  final WebViewController webView;
  final _messages = StreamController<String>.broadcast();
  bool _disposed = false;

  Future<void> _setUp() async {
    try {
      await webView.setJavaScriptMode(JavaScriptMode.unrestricted);
      await webView.setBackgroundColor(Colors.transparent);
      await webView.enableZoom(false);
      if (kDebugMode) {
        // Page console in the app log (debug builds only).
        await webView.setOnConsoleMessage(
          (m) => _log.debug('console', {
            'level': m.level.name,
            'message': m.message,
          }),
        );
      }
      await webView.addJavaScriptChannel(
        channel,
        onMessageReceived: (m) => _add(m.message),
      );
      await webView.setNavigationDelegate(
        NavigationDelegate(
          // Only this server's pages, and the blank page dispose() loads
          // (iOS asks the delegate even for programmatic loads).
          onNavigationRequest: (r) =>
              _server.owns(r.url) || (_disposed && r.url == _blank)
              ? NavigationDecision.navigate
              : NavigationDecision.prevent,
          onPageStarted: (url) {
            if (_server.owns(url)) _add(jsonEncode({'type': 'pageStarted'}));
          },
          onWebResourceError: (e) {
            if (e.isForMainFrame ?? true) {
              _add(
                jsonEncode({
                  'type': 'error',
                  'code': 'page',
                  'message': '${e.errorCode} ${e.description}',
                }),
              );
            }
          },
        ),
      );
      await webView.loadRequest(_server.pageUri);
    } on Object catch (e) {
      _add(jsonEncode({'type': 'error', 'code': 'page', 'message': '$e'}));
    }
  }

  void _add(String m) {
    if (!_disposed) _messages.add(m);
  }

  @override
  Stream<String> get messages => _messages.stream;

  @override
  Future<void> send(Map<String, Object?> command) =>
      webView.runJavaScript(avatarCommandScript(command));

  @override
  Widget buildView() => WebViewWidget(controller: webView);

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _messages.close();
    // Leave a blank page so the engine's render loop and timers stop.
    await webView.loadRequest(Uri.parse(_blank)).catchError((_) {});
  }
}

/// Whether this platform has a WebView (false in `flutter test` and on
/// platforms without the plugin).
bool get webViewAvailable => WebViewPlatform.instance != null;

/// The avatar where no WebView exists: it reports `unsupported` once, so
/// the app keeps the placeholder and the captions.
class UnavailableAvatarSurface implements AvatarSurface {
  new() {
    scheduleMicrotask(() {
      if (_messages.isClosed) return;
      _messages
        ..add(jsonEncode({'type': 'loaded'}))
        ..add(
          jsonEncode({
            'type': 'error',
            'code': 'unsupported',
            'message': 'no WebView on this platform',
          }),
        );
    });
  }

  final _messages = StreamController<String>.broadcast();

  @override
  Stream<String> get messages => _messages.stream;

  @override
  Future<void> send(Map<String, Object?> command) async {}

  @override
  Widget buildView() => const SizedBox.expand();

  @override
  Future<void> dispose() => _messages.close();
}
