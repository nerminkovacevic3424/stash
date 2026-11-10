import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';

import 'data/repo.dart';
import 'data/store.dart';
import 'services/api.dart';
import 'services/sync.dart';
import 'share/share_sheet.dart';
import 'ui/home_screen.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final repo = await Repo.open();
  await SyncService.init();
  final store = Store(repo, backendUrl: await repo.kv(backendUrlKey));
  await store.reload();
  runApp(StashApp(store: store));
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
  const StashApp({super.key, required this.store});
  final Store store;

  @override
  State<StashApp> createState() => _StashAppState();
}

class _StashAppState extends State<StashApp> with WidgetsBindingObserver {
  StreamSubscription<List<ConnectivityResult>>? _connectivity;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(widget.store.background());
    _connectivity = Connectivity().onConnectivityChanged.listen((results) {
      if (results.any((r) => r != ConnectivityResult.none)) unawaited(widget.store.background());
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The share sheet writes from another process while we are in the
    // background, so re-read on every return and finish any queued work.
    if (state == AppLifecycleState.resumed) {
      unawaited(widget.store.reload().then((_) => widget.store.background()));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _connectivity?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Stash',
    debugShowCheckedModeBanner: false,
    theme: buildTheme(Brightness.light),
    darkTheme: buildTheme(Brightness.dark),
    home: HomeScreen(store: widget.store),
  );
}
