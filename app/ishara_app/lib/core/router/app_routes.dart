/// Every route of the app. Paths are the only place route strings appear.
abstract final class AppRoutes {
  static const splash = '/';
  static const welcome = '/welcome';
  static const setup = '/setup';
  static const pair = '/pair';
  static const calibrate = '/calibrate';
  static const ready = '/ready';
  static const talk = '/talk';
  static const learn = '/learn';
  static const history = '/history';
  static const settings = '/settings';
  static const avatarStudio = '/avatar';

  static const authPath = '/auth';
  static const missionPath = '/mission/:moduleId';

  /// Login / create account (`data-arg="signin" | "signup"`).
  static String auth({required bool signUp}) =>
      '$authPath?mode=${signUp ? 'signup' : 'signin'}';

  static String mission(String moduleId) =>
      '/mission/${Uri.encodeComponent(moduleId)}';

  /// The 4 tabs, in tab-bar order (prototype `TABS`).
  static const List<String> tabs = [talk, learn, history, settings];
}
