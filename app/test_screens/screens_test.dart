// Renders the main screens to PNGs for design review (not a regression test):
//
//   flutter test test_screens --update-goldens
//
// Output lands in test_screens/shots/. Uses seeded data and painted stand-in
// images, so no device, backend or network is needed.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:stash/data/repo.dart';
import 'package:stash/data/store.dart';
import 'package:stash/models.dart';
import 'package:stash/services/api.dart';
import 'package:stash/share/share_sheet.dart';
import 'package:stash/ui/account_screen.dart';
import 'package:stash/ui/folder_screen.dart';
import 'package:stash/ui/folder_sheets.dart';
import 'package:stash/ui/home_screen.dart';
import 'package:stash/ui/search_screen.dart';
import 'package:stash/ui/theme.dart';
import 'package:stash/ui/widgets.dart';

class _Painted extends ImageProvider<_Painted> {
  const _Painted(this.image);
  final ui.Image image;

  @override
  Future<_Painted> obtainKey(ImageConfiguration configuration) => SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(_Painted key, ImageDecoderCallback decode) =>
      OneFrameImageStreamCompleter(SynchronousFuture(ImageInfo(image: image.clone())));
}

final _images = <ui.Image>[];

Future<void> _paintImages() async {
  const palettes = [
    [Color(0xFFFFB199), Color(0xFFFF0844)],
    [Color(0xFF43E97B), Color(0xFF38F9D7)],
    [Color(0xFF4FACFE), Color(0xFF00F2FE)],
    [Color(0xFFFA709A), Color(0xFFFEE140)],
    [Color(0xFF30CFD0), Color(0xFF330867)],
    [Color(0xFFA18CD1), Color(0xFFFBC2EB)],
    [Color(0xFFF6D365), Color(0xFFFDA085)],
    [Color(0xFF5EE7DF), Color(0xFFB490CA)],
  ];
  for (final p in palettes) {
    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec);
    const size = Size(200, 250);
    canvas.drawRect(
      Offset.zero & size,
      Paint()..shader = ui.Gradient.linear(Offset.zero, size.bottomRight(Offset.zero), p),
    );
    canvas.drawCircle(const Offset(140, 80), 60, Paint()..color = const Color(0x33FFFFFF));
    canvas.drawCircle(const Offset(50, 200), 80, Paint()..color = const Color(0x22000000));
    _images.add(await rec.endRecording().toImage(200, 250));
  }
}

class _FakeApi extends Api {
  _FakeApi(this.folderId);
  final String folderId;

  @override
  Future<bool> ping() async => true;

  @override
  Future<PostMeta?> metadata(String url, {Duration timeout = const Duration(seconds: 8)}) async => PostMeta(
    url: url,
    resolved: true,
    author: 'pasta.grannies',
    caption: 'Creamy garlic butter pasta in 15 minutes. Save this for a lazy weeknight #pasta #dinner',
    thumbnailUrl: 'img3',
    ok: true,
  );

  @override
  Future<AiAnswer> suggest({
    required Platform2 platform,
    required String? author,
    required String? caption,
    required String? thumbnailUrl,
    required List<String> hashtags,
    required List<Folder> folders,
    required Map<String, List<String>> examples,
    required List<Map<String, String>> hints,
    Duration timeout = const Duration(seconds: 8),
  }) async => AiAnswer(
    suggestion: FolderSuggestion.existing(folderId, SuggestionSource.ai),
    description: 'A 15-minute creamy garlic butter pasta recipe',
  );
}

Future<void> _loadFonts() async {
  final dir = '${Platform.environment['USERPROFILE']}/flutter/bin/cache/artifacts/material_fonts';
  Future<ByteData> bytes(String path) async => ByteData.view((await File(path).readAsBytes()).buffer);
  final roboto = FontLoader('Roboto');
  for (final w in ['regular', 'medium', 'bold', 'black']) {
    roboto.addFont(bytes('$dir/roboto-$w.ttf'));
  }
  await roboto.load();
  await (FontLoader('MaterialIcons')..addFont(bytes('$dir/materialicons-regular.otf'))).load();
  final emoji = File('C:/Windows/Fonts/seguiemj.ttf');
  if (emoji.existsSync()) await (FontLoader('Emoji')..addFont(bytes(emoji.path))).load();
}

const _posts = [
  (
    'Recipes',
    'instagram',
    'pasta.grannies',
    'Creamy garlic butter pasta in 15 minutes #pasta #dinner',
    'Try with lemon',
  ),
  ('Recipes', 'tiktok', 'bakewithmia', 'The only banana bread recipe you will ever need', null),
  ('Recipes', 'instagram', 'weeknight.kitchen', 'Sheet pan chicken with crispy potatoes', null),
  ('Recipes', 'tiktok', 'ramenlab', 'Spicy miso ramen from scratch, step by step', null),
  ('Travel', 'instagram', 'slowtravel', 'Hidden beaches in southern Albania you need to see', null),
  ('Travel', 'tiktok', 'lisbon.local', '48 hours in Lisbon: where to eat, what to skip', null),
  ('Travel', 'instagram', 'trainlines', 'The most scenic rail route in Switzerland', null),
  ('Workouts', 'tiktok', 'coach.dani', '10 minute core routine, no equipment', null),
  ('Workouts', 'instagram', 'mobilityfix', 'Fix tight hips with these three stretches', null),
  ('Home ideas', 'instagram', 'smallspaces', 'Renter friendly kitchen makeover under 200', null),
  ('Funny', 'tiktok', 'catdistributor', 'He does this every single morning', null),
];

const _descriptions = [
  'A 15-minute creamy garlic butter pasta recipe',
  'One-pan chicken thighs with crispy potatoes, lemon and garlic for busy weeknights',
  'Quiet beaches on the southern Albanian coast',
  'The most scenic train ride through the Swiss Alps',
  'Three stretches that loosen tight hips',
  'A cat with a very strict morning routine',
];

Future<Repo> _seed() async {
  final repo = await Repo.open(path: inMemoryDatabasePath, factory: databaseFactoryFfiNoIsolate);
  final ids = <String, String>{};
  for (final (name, emoji, color) in [
    ('Recipes', '🍳', 2),
    ('Travel', '✈️', 6),
    ('Workouts', '🏋️', 4),
    ('Home ideas', '🛋️', 3),
    ('Funny', '😂', 7),
    ('Gift ideas', '🎁', 1),
  ]) {
    ids[name] = (await repo.createFolder(name, emoji: emoji, color: color)).id;
  }
  var i = 0;
  for (final (folder, platform, author, caption, note) in _posts) {
    final url = platform == 'tiktok'
        ? 'https://www.tiktok.com/@$author/video/10$i'
        : 'https://www.instagram.com/reel/SEED$i/';
    await repo.insertPost(
      link: LinkInfo(platform: Platform2.parse(platform), url: url, author: author),
      sourceUrl: url,
      folderId: ids[folder]!,
      meta: PostMeta(url: url, resolved: true, author: author, caption: caption, thumbnailUrl: 'img$i', ok: true),
      note: note,
      aiDescription: i.isEven ? _descriptions[i ~/ 2 % _descriptions.length] : null,
      aiDone: true,
    );
    // Spread the save dates so "Today / Yesterday / 12 Mar" all show up.
    await repo.db.rawUpdate('UPDATE posts SET created_at = created_at - ? WHERE url = ?', [
      (_posts.length - i - 1) * 30 * 3600 * 1000,
      url,
    ]);
    i++;
  }
  return repo;
}

void main() {
  sqfliteFfiInit();

  setUpAll(() async {
    await _loadFonts();
    await _paintImages();
    postImageProvider = (url) =>
        _Painted(_images[(int.tryParse(url.replaceAll(RegExp(r'\D'), '')) ?? 0) % _images.length]);
  });

  Future<void> shot(
    WidgetTester tester,
    String name,
    Future<Widget> Function(Repo repo, Store store) build, {
    Brightness brightness = Brightness.light,
    Future<void> Function()? after,
  }) async {
    tester.view.physicalSize = const Size(390 * 2, 844 * 2);
    tester.view.devicePixelRatio = 2;
    tester.view.padding = const FakeViewPadding(top: 94, bottom: 68);
    addTearDown(tester.view.reset);

    late Repo repo;
    late Store store;
    late Widget child;
    await tester.runAsync(() async {
      repo = await _seed();
      store = Store(repo);
      await store.reload();
      child = await build(repo, store);
    });

    debugDisableShadows = false;
    final theme = buildTheme(brightness, fontFamily: 'Roboto', fontFamilyFallback: const ['Emoji']);
    await tester.pumpWidget(MaterialApp(debugShowCheckedModeBanner: false, theme: theme, home: child));
    // Let real database futures and timers settle, then draw.
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
      await tester.pump(const Duration(milliseconds: 300));
    }
    if (after != null) {
      await after();
      for (var i = 0; i < 4; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
        await tester.pump(const Duration(milliseconds: 300));
      }
    }
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('shots/$name.png'));
    debugDisableShadows = true;
    await tester.runAsync(() => repo.db.close());
  }

  Widget overPost(Widget sheet) => Stack(
    fit: StackFit.expand,
    children: [
      const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF2B2B3A), Color(0xFF8A5A44), Color(0xFF1A1A1F)],
          ),
        ),
      ),
      sheet,
    ],
  );

  Future<Widget> shareSheet(Repo repo, {String? link}) async {
    final recipes = (await repo.folders()).firstWhere((f) => f.name == 'Recipes');
    return overPost(
      ShareSheet(
        repo: repo,
        api: _FakeApi(recipes.id),
        sharedText: link ?? 'https://www.instagram.com/reel/NEWPOST1/',
        onClose: () {},
      ),
    );
  }

  testWidgets('home', (t) => shot(t, 'home_light', (_, store) async => HomeScreen(store: store)));

  testWidgets(
    'home dark',
    (t) => shot(t, 'home_dark', (_, store) async => HomeScreen(store: store), brightness: Brightness.dark),
  );

  testWidgets('home empty', (t) async {
    await shot(t, 'home_empty', (repo, store) async {
      await repo.db.delete('posts');
      await repo.db.delete('folders', where: "id != 'unsorted'");
      await store.reload();
      return HomeScreen(store: store);
    });
  });

  testWidgets('folder', (t) async {
    await shot(t, 'folder_light', (repo, store) async {
      final f = store.folders.firstWhere((f) => f.name == 'Recipes');
      return FolderScreen(store: store, folderId: f.id);
    });
  });

  testWidgets('folder dark', (t) async {
    await shot(t, 'folder_dark', (repo, store) async {
      final f = store.folders.firstWhere((f) => f.name == 'Travel');
      return FolderScreen(store: store, folderId: f.id);
    }, brightness: Brightness.dark);
  });

  testWidgets('search', (t) async {
    await shot(
      t,
      'search',
      (_, store) async => SearchScreen(store: store),
      after: () => t.enterText(find.byType(TextField), 'in'),
    );
  });

  testWidgets('folder editor', (t) async {
    await shot(
      t,
      'folder_editor',
      (_, store) async => Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(onPressed: () => showFolderEditor(context), child: const Text('open')),
          ),
        ),
      ),
      after: () => t.tap(find.text('open')),
    );
  });

  testWidgets('settings', (t) => shot(t, 'settings', (_, store) async => AccountScreen(store: store)));

  testWidgets('folder expanded', (t) async {
    await shot(t, 'folder_expanded', (repo, store) async {
      final f = store.folders.firstWhere((f) => f.name == 'Recipes');
      return FolderScreen(store: store, folderId: f.id);
    }, after: () => t.tap(find.text('Show more').first));
  });

  testWidgets('post details', (t) async {
    await shot(t, 'post_details', (repo, store) async {
      final f = store.folders.firstWhere((f) => f.name == 'Recipes');
      return FolderScreen(store: store, folderId: f.id);
    }, after: () => t.longPress(find.textContaining('@pasta.grannies')));
  });

  testWidgets('folder without previews', (t) async {
    await shot(t, 'folder_no_previews', (repo, store) async {
      await repo.db.update('posts', {'thumbnail_url': null});
      await store.reload();
      final f = store.folders.firstWhere((f) => f.name == 'Travel');
      return FolderScreen(store: store, folderId: f.id);
    });
  });

  testWidgets('share by ai', (t) async {
    await shot(t, 'share_ai', (repo, _) async {
      // An author Stash has not seen before, so the folder comes from the AI.
      await repo.db.update('posts', {'author': 'someone.else'}, where: "author = 'pasta.grannies'");
      return shareSheet(repo);
    });
  });

  testWidgets('share', (t) => shot(t, 'share_light', (repo, _) => shareSheet(repo)));

  testWidgets('share dark', (t) => shot(t, 'share_dark', (repo, _) => shareSheet(repo), brightness: Brightness.dark));

  testWidgets('share picker', (t) async {
    await shot(t, 'share_picker', (repo, _) => shareSheet(repo), after: () => t.tap(find.text('Change')));
  });

  testWidgets('share duplicate', (t) async {
    await shot(t, 'share_duplicate', (repo, _) => shareSheet(repo, link: 'https://www.instagram.com/reel/SEED4/'));
  });

  testWidgets('share saved', (t) async {
    await shot(t, 'share_saved', (repo, _) => shareSheet(repo), after: () => t.tap(find.text('Save')));
  });
}
