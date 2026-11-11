import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:stash/data/repo.dart';
import 'package:stash/models.dart';
import 'package:stash/services/api.dart';
import 'package:stash/services/device_meta.dart';
import 'package:stash/services/link_parser.dart';
import 'package:stash/services/pending_queue.dart';
import 'package:stash/services/suggester.dart';
import 'package:stash/share/share_controller.dart';

class FakeApi extends Api {
  bool online = true;
  Duration delay = Duration.zero;
  int suggestCalls = 0;

  /// What the "LLM" answers, given the folders it was shown.
  FolderSuggestion? Function(List<Folder> folders)? answer;

  @override
  Future<bool> ping() async => online;

  @override
  Future<(List<String>, String?)> extract({required Platform2 platform, required String caption}) async {
    if (!online) throw Unreachable();
    return (const ['200 g pasta', '2 cloves garlic'], null);
  }

  @override
  Future<PostMeta?> metadata(String url, {Duration timeout = const Duration(seconds: 8)}) async {
    await Future<void>.delayed(delay);
    if (!online) throw Unreachable();
    final author = canonicalize(url)?.author ?? 'chef.anna';
    return PostMeta(
      url: url,
      resolved: true,
      author: author,
      caption: 'Creamy garlic #pasta in 15 minutes #dinner. You need 200 g pasta, 2 cloves garlic and cream.',
      thumbnailUrl: 'https://example.com/t.jpg',
      ok: true,
    );
  }

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
  }) async {
    if (!online) throw Unreachable();
    suggestCalls++;
    return AiAnswer(
      suggestion: answer?.call(folders),
      description: 'A quick creamy garlic pasta recipe',
      tags: const ['pasta', 'quick dinner'],
    );
  }
}

const reel1 = 'https://www.instagram.com/reel/AAA111/?igsh=x';
const reel2 = 'Look at this https://www.instagram.com/reel/BBB222/';

void main() {
  sqfliteFfiInit();
  late Repo repo;
  late FakeApi api;

  setUp(() async {
    repo = await Repo.open(path: inMemoryDatabasePath, factory: databaseFactoryFfiNoIsolate);
    api = FakeApi();
  });
  tearDown(() => repo.db.close());

  Future<ShareController> share(String text) async {
    final c = ShareController(repo, api);
    await c.start(text);
    return c;
  }

  test('parses shared text', () {
    expect(extractUrl('wow https://vm.tiktok.com/ZMabc/ !!'), 'https://vm.tiktok.com/ZMabc/');
    expect(extractUrl('see https://example.com/a then https://youtu.be/dQw4w9WgXcQ'), 'https://youtu.be/dQw4w9WgXcQ');
    expect(extractUrl('just words'), isNull);
    expect(canonicalize('https://instagram.com/reels/Cabc/?x=1')!.url, 'https://www.instagram.com/reel/Cabc/');
    expect(canonicalize('https://www.instagram.com/share/reel/BAx')!.needsResolve, isTrue);
    final t = canonicalize('https://www.tiktok.com/@Some.User/video/73012?lang=en')!;
    expect(t.url, 'https://www.tiktok.com/@Some.User/video/73012');
    expect(t.author, 'some.user');
    expect(canonicalize('https://vm.tiktok.com/ZMabc/')!.needsResolve, isTrue);
    // YouTube, Facebook, X and any other site
    expect(canonicalize('https://youtu.be/dQw4w9WgXcQ?si=abc')!.url, 'https://www.youtube.com/watch?v=dQw4w9WgXcQ');
    expect(canonicalize('https://m.youtube.com/watch?v=dQw4w9WgXcQ&t=10s&feature=share')!.platform, Platform2.youtube);
    expect(
      canonicalize('https://youtube.com/shorts/abcDEF12345?feature=share')!.url,
      'https://www.youtube.com/shorts/abcDEF12345',
    );
    expect(canonicalize('https://fb.watch/abc123/')!.needsResolve, isTrue);
    expect(
      canonicalize('https://m.facebook.com/watch/?v=123&mibextid=xyz')!.url,
      'https://www.facebook.com/watch/?v=123',
    );
    final tweet = canonicalize('https://twitter.com/NASA/status/141?s=20&t=abc')!;
    expect(tweet.url, 'https://x.com/NASA/status/141');
    expect(tweet.author, 'nasa');
    final other = canonicalize('https://vimeo.com/76979871?utm_source=x&share=copy#t=1')!;
    expect(other.platform, Platform2.other);
    expect(other.url, 'https://vimeo.com/76979871?share=copy');
    expect(sourceLabel(other.platform, other.url), 'vimeo.com');
    expect(canonicalize('not a link'), isNull);
    expect(keywordsOf('Easy #Pasta night with garlic'), {'pasta': 2, 'easy': 1, 'night': 1, 'garlic': 1});
  });

  test('reads previews from the pages the platforms publish', () {
    final tt = parseTikTokPage(
      '<html><script id="__UNIVERSAL_DATA_FOR_REHYDRATION__" type="application/json">'
      '{"__DEFAULT_SCOPE__":{"webapp.video-detail":{"itemInfo":{"itemStruct":{"desc":"Easy ramen #food",'
      '"video":{"cover":"https://p16.tiktokcdn.com/c.jpg"},"author":{"uniqueId":"RamenLab","nickname":"Ramen Lab"}}}}}}'
      '</script></html>',
    );
    expect(tt.caption, 'Easy ramen #food');
    expect(tt.thumbnailUrl, 'https://p16.tiktokcdn.com/c.jpg');
    expect(tt.author, 'ramenlab');
    expect(parseTikTokPage('<html>nothing here</html>').caption, isNull);

    final embed = parseInstagramEmbed(
      '<img class="EmbeddedMediaImage" alt="x" src="https://scontent.cdninstagram.com/a.jpg?x=1&amp;y=2">'
      '<span class="UsernameText">Chef.Anna</span>'
      '<div class="Caption"><a class="CaptionUsername" href="#">chef.anna</a><br /><br />'
      'Lemon pasta &#064;home <a href="/t">#dinner</a><div class="CaptionComments">',
    );
    expect(embed.thumbnailUrl, 'https://scontent.cdninstagram.com/a.jpg?x=1&y=2');
    expect(embed.author, 'chef.anna');
    expect(embed.caption, 'Lemon pasta @home #dinner');

    final page = parseInstagramPage(
      '<meta property="og:title" content="Anna on Instagram: &quot;Lemon pasta&quot;" />'
      '<meta property="og:url" content="https://www.instagram.com/chef.anna/reel/Cabc/" />'
      '<meta property="og:image" content="https://scontent.cdninstagram.com/b.jpg" />',
    );
    expect(page.caption, 'Lemon pasta');
    expect(page.author, 'chef.anna');
    expect(page.thumbnailUrl, 'https://scontent.cdninstagram.com/b.jpg');
  });

  test('a late AI answer replaces the fallback while the sheet is still untouched', () async {
    final travel = await repo.createFolder('Travel');
    final recipes = await repo.createFolder('Recipes');
    await repo.setKv('last_folder', travel.id);
    api.delay = const Duration(seconds: 2);
    api.answer = (_) => FolderSuggestion.existing(recipes.id, SuggestionSource.ai);

    final c = ShareController(repo, api);
    final started = c.start(reel1);
    await Future<void>.delayed(const Duration(milliseconds: 1700));
    expect(c.selected?.id, travel.id);
    await started;
    expect(c.selected?.id, recipes.id);
    expect(c.suggestion?.source, SuggestionSource.ai);
  });

  test('saved to the fallback, then sorted when the AI answers before the sheet closes', () async {
    final recipes = await repo.createFolder('Recipes');
    api.delay = const Duration(seconds: 2);
    api.answer = (_) => FolderSuggestion.existing(recipes.id, SuggestionSource.ai);

    final c = ShareController(repo, api);
    final started = c.start(reel1);
    await Future<void>.delayed(const Duration(milliseconds: 1700));
    await c.save('');
    expect(c.confirmation, 'Saved to Unsorted');
    await started;
    final post = (await repo.posts()).single;
    expect(post.folderId, recipes.id);
    expect(post.needsSuggestion, isFalse);
  });

  test('favorites, platform list and the shared title as a stand-in caption', () async {
    api.online = false; // no preview available
    final c = await share('Watch "Knife skills 101" on YouTube https://youtu.be/dQw4w9WgXcQ');
    expect(c.link?.platform, Platform2.youtube);
    expect(c.meta?.caption, 'Watch "Knife skills 101" on YouTube');
    await c.save('');
    api.online = true;
    await (await share(reel1)).save('');

    final yt = (await repo.posts(platform: Platform2.youtube)).single;
    expect(yt.caption, contains('Knife skills'));
    expect(await repo.platforms(), unorderedEquals([Platform2.youtube, Platform2.instagram]));

    await repo.setFavorite(yt.id, true);
    expect((await repo.posts(favorite: true)).single.id, yt.id);
    expect(await repo.counts(), (2, 1, 2));
    expect(await repo.platforms(favorite: true), [Platform2.youtube]);
  });

  test('tags, key points, watched and bulk changes', () async {
    final recipes = await repo.createFolder('Recipes');
    api.answer = (_) => FolderSuggestion.existing(recipes.id, SuggestionSource.ai);
    await (await share(reel1)).save('');
    await (await share('https://www.tiktok.com/@other/video/42')).save('');

    var post = (await repo.posts(tag: 'pasta')).first;
    expect(post.tags, ['pasta', 'quick dinner']);
    expect(await repo.posts(tag: 'past'), isEmpty); // whole tags only
    expect((await repo.topTags()).first.key, anyOf('pasta', 'quick dinner'));
    expect(await repo.posts(query: 'quick dinner'), isNotEmpty);

    // The queue mines the caption for the practical part.
    await PendingQueue(repo, api, Suggester(repo, api)).process();
    post = (await repo.post(post.id))!;
    expect(post.points, ['200 g pasta', '2 cloves garlic']);
    expect(await repo.pendingExtract(), isEmpty);

    expect(await repo.counts(), (2, 0, 2));
    final ids = [for (final p in await repo.posts()) p.id];
    await repo.setWatched(ids, true);
    expect(await repo.posts(watched: false), isEmpty);
    await repo.setFavorites(ids, true);
    expect(await repo.counts(), (2, 2, 0));
    await repo.deletePosts(ids);
    expect(await repo.posts(), isEmpty);
  });

  test('a folder sent as text is imported as one folder', () async {
    final c = await share(
      '📁 Trip ideas — shared from Stash\n\nHidden beaches\nhttps://www.instagram.com/reel/AAA111/\n\n'
      'https://youtu.be/dQw4w9WgXcQ\nhttps://vimeo.com/76979871\nhttps://youtu.be/dQw4w9WgXcQ',
    );
    expect(c.isBulk, isTrue);
    expect(c.bulk, hasLength(3)); // the repeated link counts once
    expect(c.newName, 'Trip ideas');
    await c.save('');
    expect(c.confirmation, 'Saved 3 to Trip ideas');
    final folder = (await repo.folders()).firstWhere((f) => f.name == 'Trip ideas');
    expect(await repo.posts(folderId: folder.id), hasLength(3));

    // Sharing it again adds nothing and reuses the folder.
    final again = await share(
      '📁 Trip ideas — shared from Stash\nhttps://youtu.be/dQw4w9WgXcQ\nhttps://vimeo.com/76979871',
    );
    expect(again.selected?.id, folder.id);
    await again.save('');
    expect(again.confirmation, 'Already saved');
  });

  test('merging folders moves the posts and removes the source', () async {
    final food = await repo.createFolder('Food');
    final recipes = await repo.createFolder('Recipes');
    api.answer = (_) => FolderSuggestion.existing(food.id, SuggestionSource.ai);
    await (await share(reel1)).save('');
    await repo.mergeFolders(food.id, recipes.id);
    expect(await repo.folder(food.id), isNull);
    expect(await repo.posts(folderId: recipes.id), hasLength(1));
    expect(await repo.authorRule(Platform2.instagram, 'chef.anna'), isNull);
  });

  test('AI suggestion is pre-selected and saved in one step', () async {
    final recipes = await repo.createFolder('Recipes', emoji: '🍳');
    api.answer = (_) => FolderSuggestion.existing(recipes.id, SuggestionSource.ai);

    final c = await share(reel1);
    expect(c.suggesting, isFalse);
    expect(c.selected?.id, recipes.id);

    await c.save('');
    expect(c.stage, ShareStage.saved);
    expect(c.confirmation, 'Saved to Recipes');
    final post = (await repo.posts(folderId: recipes.id)).single;
    expect(post.url, 'https://www.instagram.com/reel/AAA111/');
    expect(post.author, 'chef.anna');
    expect(post.metaStatus, 1);
    expect(post.needsSuggestion, isFalse);
    expect(post.aiDescription, 'A quick creamy garlic pasta recipe');
    expect(await repo.pendingAi(), isEmpty);
  });

  test('same author goes to the same folder without asking the AI', () async {
    final recipes = await repo.createFolder('Recipes');
    api.answer = (_) => FolderSuggestion.existing(recipes.id, SuggestionSource.ai);
    await (await share(reel1)).save('');
    expect(api.suggestCalls, 1);

    final c = await share(reel2);
    expect(c.suggestion?.source, SuggestionSource.author);
    expect(c.selected?.id, recipes.id);
    expect(api.suggestCalls, 1);
  });

  test('AI can propose a new folder, created on save', () async {
    api.answer = (_) => const FolderSuggestion.create('Recipes', '🍳');
    final c = await share(reel1);
    expect(c.newName, 'Recipes');
    await c.save('try this weekend');
    final folder = (await repo.folders()).firstWhere((f) => f.name == 'Recipes');
    expect(folder.emoji, '🍳');
    expect((await repo.posts(folderId: folder.id)).single.note, 'try this weekend');
  });

  test('overriding a suggestion teaches author and keywords', () async {
    final recipes = await repo.createFolder('Recipes');
    final dinner = await repo.createFolder('Dinner ideas');
    api.answer = (_) => FolderSuggestion.existing(recipes.id, SuggestionSource.ai);

    final c = await share(reel1);
    c.pick(dinner);
    await c.save('');

    expect(await repo.authorRule(Platform2.instagram, 'chef.anna'), dinner.id);
    // A different author with a similar caption now matches on keywords alone.
    final s = await Suggester(
      repo,
      api,
    ).local(platform: Platform2.tiktok, author: 'someone.else', caption: 'Weeknight #pasta #dinner');
    expect(s?.folderId, dinner.id);
    expect(s?.source, SuggestionSource.keywords);
  });

  test('offline: saves the bare URL, then the queue fills it in and re-files it', () async {
    final recipes = await repo.createFolder('Recipes');
    api.online = false;

    final c = await share(reel1);
    expect(c.meta, isNull);
    expect(c.selected?.id, unsortedId);
    await c.save('');
    var post = (await repo.posts()).single;
    expect(post.metaStatus, 0);
    expect(post.needsSuggestion, isTrue);

    final queue = PendingQueue(repo, api, Suggester(repo, api));
    expect(await queue.process(), isFalse); // still offline

    api.online = true;
    api.answer = (_) => FolderSuggestion.existing(recipes.id, SuggestionSource.ai);
    expect(await queue.process(), isTrue);
    post = (await repo.posts()).single;
    expect(post.caption, contains('pasta'));
    expect(post.folderId, recipes.id);
    expect(post.needsSuggestion, isFalse);
  });

  test('queue sorts by content: creates the folder the AI proposes and adds a description', () async {
    api.online = false;
    await (await share(reel1)).save('');
    expect((await repo.posts()).single.folderId, unsortedId);

    api.online = true;
    api.answer = (_) => const FolderSuggestion.create('Recipes', '🍳');
    expect(await PendingQueue(repo, api, Suggester(repo, api)).process(), isTrue);

    final recipes = (await repo.folders()).firstWhere((f) => f.name == 'Recipes');
    final post = (await repo.posts()).single;
    expect(post.folderId, recipes.id);
    expect(post.aiDescription, 'A quick creamy garlic pasta recipe');
    expect((await repo.posts(query: 'quick creamy')), hasLength(1));
  });

  test('queue describes posts filed by author history without moving them', () async {
    final recipes = await repo.createFolder('Recipes');
    final other = await repo.createFolder('Other');
    api.answer = (_) => FolderSuggestion.existing(recipes.id, SuggestionSource.ai);
    await (await share(reel1)).save('');

    // Second post from the same author: filed locally, the AI is never asked in the sheet.
    await (await share(reel2)).save('');
    expect(await repo.pendingAi(), hasLength(1));

    api.answer = (_) => FolderSuggestion.existing(other.id, SuggestionSource.ai);
    await PendingQueue(repo, api, Suggester(repo, api)).process();
    final posts = await repo.posts(folderId: recipes.id);
    expect(posts, hasLength(2));
    expect(posts.every((p) => p.aiDescription != null), isTrue);
  });

  test('slow network: falls back to last used once the budget runs out', () async {
    final travel = await repo.createFolder('Travel');
    await repo.setKv('last_folder', travel.id);
    api.delay = const Duration(seconds: 3);

    final c = ShareController(repo, api);
    final started = c.start(reel1);
    await Future<void>.delayed(const Duration(milliseconds: 1700));
    expect(c.suggestion?.source, SuggestionSource.lastUsed);
    expect(c.selected?.id, travel.id);
    await started;
    expect(c.selected?.id, travel.id); // a late answer must not move the chip
  });

  test('duplicate: says where it is and offers to move it', () async {
    final recipes = await repo.createFolder('Recipes');
    final travel = await repo.createFolder('Travel');
    api.answer = (_) => FolderSuggestion.existing(recipes.id, SuggestionSource.ai);
    await (await share(reel1)).save('');

    final c = await share('$reel1&utm=1');
    expect(c.duplicate, isNotNull);
    expect(c.duplicateInPlace, isTrue);
    c.pick(travel);
    expect(c.duplicateInPlace, isFalse);
    await c.save('');
    expect(c.confirmation, 'Moved to Travel');
    expect(await repo.posts(), hasLength(1));
    expect((await repo.posts(folderId: travel.id)), hasLength(1));
  });

  test('deleting a folder can keep its posts in Unsorted', () async {
    final recipes = await repo.createFolder('Recipes');
    api.answer = (_) => FolderSuggestion.existing(recipes.id, SuggestionSource.ai);
    await (await share(reel1)).save('');
    await repo.deleteFolder(recipes.id, deletePosts: false);
    expect((await repo.posts(folderId: unsortedId)), hasLength(1));
    expect((await repo.posts(query: 'GARLIC')), hasLength(1));
    expect((await repo.posts(query: 'garlic', platform: Platform2.tiktok)), isEmpty);
  });
}
