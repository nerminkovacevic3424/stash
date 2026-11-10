import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:stash/data/repo.dart';
import 'package:stash/models.dart';
import 'package:stash/services/api.dart';
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
  Future<PostMeta?> metadata(String url, {Duration timeout = const Duration(seconds: 8)}) async {
    await Future<void>.delayed(delay);
    if (!online) throw Unreachable();
    final author = canonicalize(url)?.author ?? 'chef.anna';
    return PostMeta(
      url: url,
      resolved: true,
      author: author,
      caption: 'Creamy garlic #pasta in 15 minutes #dinner',
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
    return AiAnswer(suggestion: answer?.call(folders), description: 'A quick creamy garlic pasta recipe');
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
    expect(extractUrl('https://example.com/instagram.com/p/x'), isNull);
    expect(canonicalize('https://instagram.com/reels/Cabc/?x=1')!.url, 'https://www.instagram.com/reel/Cabc/');
    expect(canonicalize('https://www.instagram.com/share/reel/BAx')!.needsResolve, isTrue);
    final t = canonicalize('https://www.tiktok.com/@Some.User/video/73012?lang=en')!;
    expect(t.url, 'https://www.tiktok.com/@Some.User/video/73012');
    expect(t.author, 'some.user');
    expect(canonicalize('https://vm.tiktok.com/ZMabc/')!.needsResolve, isTrue);
    expect(keywordsOf('Easy #Pasta night with garlic'), {'pasta': 2, 'easy': 1, 'night': 1, 'garlic': 1});
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
