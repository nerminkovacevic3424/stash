// ignore_for_file: avoid_print
// Fetches a post's preview the way the phone does:
//   dart run tool/try_meta.dart https://www.instagram.com/reel/XXXX/
import 'package:stash/services/device_meta.dart';

Future<void> main(List<String> args) async {
  for (final url in args) {
    final sw = Stopwatch()..start();
    final m = await DeviceMeta().fetch(url);
    print('${sw.elapsedMilliseconds}ms  ok=${m?.ok}  @${m?.author}');
    print('  caption: ${m?.caption?.replaceAll('\n', ' ')}');
    print('  image:   ${m?.thumbnailUrl}');
  }
}
