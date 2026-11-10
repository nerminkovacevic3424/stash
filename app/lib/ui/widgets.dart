import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../models.dart';
import 'theme.dart';

/// Small round platform marker. Uses neutral glyphs rather than brand logos.
class PlatformBadge extends StatelessWidget {
  const PlatformBadge(this.platform, {super.key, this.size = 22});
  final Platform2 platform;
  final double size;

  @override
  Widget build(BuildContext context) {
    final ig = platform == Platform2.instagram;
    return Semantics(
      label: platform.label,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: ig ? const LinearGradient(colors: [Color(0xFFF58529), Color(0xFFDD2A7B), Color(0xFF8134AF)]) : null,
          color: ig ? null : Colors.black,
          border: Border.all(color: Colors.white, width: 1.5),
        ),
        child: Icon(
          ig ? Icons.photo_camera_outlined : Icons.music_note_rounded,
          size: size * 0.55,
          color: Colors.white,
        ),
      ),
    );
  }
}

/// How post images are loaded. Tests swap this to render without a network.
ImageProvider Function(String url) postImageProvider = CachedNetworkImageProvider.new;

/// A post image that fills its box. While loading, or when there is no
/// (working) image, it shows a soft tile tinted for the post's platform.
class PostImage extends StatelessWidget {
  const PostImage({super.key, required this.url, this.platform, this.iconSize = 28});
  final String? url;
  final Platform2? platform;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = scheme.brightness == Brightness.dark;
    final tint = switch (platform) {
      Platform2.instagram => const Color(0xFFE1306C),
      Platform2.tiktok => const Color(0xFF12A594),
      null => scheme.primary,
    };
    final base = scheme.surfaceContainerHighest;
    final placeholder = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.alphaBlend(tint.withValues(alpha: dark ? 0.34 : 0.22), base),
            Color.alphaBlend(tint.withValues(alpha: dark ? 0.12 : 0.07), base),
          ],
        ),
      ),
      child: Center(
        child: Container(
          width: iconSize * 1.7,
          height: iconSize * 1.7,
          decoration: BoxDecoration(
            color: scheme.surface.withValues(alpha: dark ? 0.35 : 0.6),
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.play_arrow_rounded, color: tint.withValues(alpha: 0.9), size: iconSize),
        ),
      ),
    );
    if (url == null) return placeholder;
    return Image(
      image: postImageProvider(url!),
      fit: BoxFit.cover,
      gaplessPlayback: true,
      frameBuilder: (_, child, frame, sync) => sync || frame != null ? child : placeholder,
      errorBuilder: (_, _, _) => placeholder,
    );
  }
}

/// Square post thumbnail with the platform badge on its corner.
class PostThumb extends StatelessWidget {
  const PostThumb({super.key, required this.url, required this.platform, this.size = 64, this.radius = 14});
  final String? url;
  final Platform2 platform;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size,
    child: Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(radius),
            child: PostImage(url: url, platform: platform, iconSize: size * 0.3),
          ),
        ),
        Positioned(right: -4, bottom: -4, child: PlatformBadge(platform, size: size < 60 ? 20 : 24)),
      ],
    ),
  );
}

/// Emoji on the folder's tinted color.
class FolderAvatar extends StatelessWidget {
  const FolderAvatar({super.key, required this.emoji, required this.color, this.size = 44});
  final String emoji;
  final int color;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: folderColor(color).withValues(alpha: 0.18),
      borderRadius: BorderRadius.circular(size * 0.3),
    ),
    child: Text(emoji, style: TextStyle(fontSize: size * 0.5)),
  );
}

/// Grey bar shown while text is loading.
class Skeleton extends StatelessWidget {
  const Skeleton({super.key, required this.width, this.height = 12});
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    height: height,
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(6),
    ),
  );
}
