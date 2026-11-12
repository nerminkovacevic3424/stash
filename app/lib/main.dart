import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'data/repo.dart';
import 'data/store.dart';
import 'services/api.dart';
import 'services/reminders.dart';
import 'services/sync.dart';
import 'share/share_sheet.dart';
import 'ui/auth_screens.dart';
import 'ui/home_screen.dart';
import 'ui/onboarding_screen.dart';
import 'ui/post_details.dart';
import 'ui/theme.dart';

const _onboardedKey = 'onboarded';
const _askedNotificationsKey = 'asked_notifications';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final repo = await Repo.open();
  await SyncService.init();
  final store = Store(repo, backendUrl: await repo.kv(backendUrlKey));
  await store.reload();
  await store.auth.load();
  // People who already have saves do not need the tour.
  final onboarded = await repo.kv(_onboardedKey) != null || store.total > 0;
  runApp(StashApp(store: store, showOnboarding: !onboarded));
}

/// Entrypoint for the Android share activity (see ShareActivity.kt).
/// On iOS the share sheet is the native extension in ios/StashShare.
@pragma('vm:entry-point')
Future<void> shareMain() async {
  WidgetsFlutterBinding.ensureInitialized();
  final repo = await Repo.open();
  runApp(
    ShareApp(
      repo: repo,
      api: Api(baseUrl: await repo.kv(backendUrlKey)),
    ),
  );
}

class StashApp extends StatefulWidget {
  const StashApp({super.key, required this.store, this.showOnboarding = false});
  final Store store;
  final bool showOnboarding;

  @override
  State<StashApp> createState() => _StashAppState();
}

class _StashAppState extends State<StashApp> with WidgetsBindingObserver {
  final _navigator = GlobalKey<NavigatorState>();
  StreamSubscription<List<ConnectivityResult>>? _connectivity;
  late bool _onboarding = widget.showOnboarding;

  Store get store => widget.store;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    store.auth.addListener(_onAuthChanged);
    _wakeAndWork();
    _connectivity = Connectivity().onConnectivityChanged.listen((results) {
      if (results.any((r) => r != ConnectivityResult.none)) unawaited(store.background());
    });

    // Tapping a reminder opens that post's details.
    Reminders.onOpen = _showPost;
    _askForNotificationsOnce();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final id = await Reminders.launchPostId();
      if (id != null) _showPost(id);
    });
  }

  /// Wakes the server (free hosting sleeps when idle) so it is ready by the
  /// time something is shared, then finishes any queued work.
  void _wakeAndWork() {
    unawaited(store.api.ping());
    unawaited(store.background());
  }

  void _onAuthChanged() {
    setState(() {});
    _askForNotificationsOnce();
  }

  /// The first time the home screen is reached, offer to turn notifications
  /// on, so reminders work later without a detour. Asked once; after that the
  /// prompt only appears when a reminder is being set.
  void _askForNotificationsOnce() {
    if (kIsWeb || _onboarding || !store.auth.signedIn) return;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (await store.repo.kv(_askedNotificationsKey) != null) return;
      await store.repo.setKv(_askedNotificationsKey, '1');
      final context = _navigator.currentContext;
      if (context != null && context.mounted) await Reminders.ensurePermission(context);
    });
  }

  Future<void> _showPost(String id) async {
    final post = await store.repo.post(id);
    final context = _navigator.currentContext;
    if (post == null || context == null || !context.mounted) return;
    // The reminder has done its job.
    await store.repo.setReminder(id, null);
    if (context.mounted) await showPostDetails(context, store, post);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The share sheet writes from another process while we are in the
    // background, so re-read on every return and finish any queued work.
    if (state == AppLifecycleState.resumed) {
      unawaited(store.reload().then((_) => _wakeAndWork()));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    store.auth.removeListener(_onAuthChanged);
    _connectivity?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Stash',
    debugShowCheckedModeBanner: false,
    navigatorKey: _navigator,
    // The layout is phone-shaped; on a wide browser window keep it to a
    // readable column instead of stretching edge to edge.
    builder: (context, child) => kIsWeb
        ? ColoredBox(
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            child: Center(
              child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 1100), child: child),
            ),
          )
        : child!,
    theme: buildTheme(Brightness.light),
    darkTheme: buildTheme(Brightness.dark),
    home: _onboarding
        ? OnboardingScreen(
            onDone: () {
              unawaited(store.repo.setKv(_onboardedKey, '1'));
              setState(() => _onboarding = false);
              _askForNotificationsOnce();
            },
          )
        : store.auth.signedIn
        ? HomeScreen(store: store)
        : SignInScreen(auth: store.auth),
  );
}
