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

  /// Developer only (debug / profile builds): every avatar sign, front and
  /// side (sign rule 2 previews).
  static const signPreview = '/dev/signs';

  static const authPath = '/auth';
  static const missionPath = '/mission/:moduleId';

  /// Login / create account (`data-arg="signin" | "signup"`).
  static String auth({required bool signUp}) =>
      '$authPath?mode=${signUp ? 'signup' : 'signin'}';

  /// Ready after calibrating, or after skipping it (prototype
  /// `state.calibrated`).
  static String readyAfter({required bool skipped}) =>
      skipped ? '$ready?skipped=1' : ready;

  /// Pair / Calibrate opened from a mission's practice step (S8-8): when
  /// done they pop [screens] screens, back to that step, instead of Ready.
  static String pairBack(int screens) => '$pair?back=$screens';
  static String calibrateBack(int screens) => '$calibrate?back=$screens';

  static String mission(String moduleId) =>
      '/mission/${Uri.encodeComponent(moduleId)}';

  /// The 4 tabs, in tab-bar order (prototype `TABS`).
  static const List<String> tabs = [talk, learn, history, settings];
}
