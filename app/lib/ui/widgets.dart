import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../models.dart';
import 'theme.dart';

/// Brand colour used to tint things that belong to a platform.
Color platformColor(Platform2 p) => switch (p) {
  Platform2.instagram => const Color(0xFFE1306C),
  Platform2.tiktok => const Color(0xFF12A594),
  Platform2.youtube => const Color(0xFFE5332A),
  Platform2.facebook => const Color(0xFF1877F2),
  Platform2.x => const Color(0xFF536471),
  Platform2.other => const Color(0xFF6E6AD8),
};

/// Small round marker saying where a post came from.
class PlatformBadge extends StatelessWidget {
  const PlatformBadge(this.platform, {super.key, this.size = 22});
  final Platform2 platform;
  final double size;

  @override
  Widget build(BuildContext context) {
    final (Color color, IconData? icon) = switch (platform) {
      Platform2.instagram => (Colors.transparent, Icons.photo_camera_outlined),
      Platform2.tiktok => (Colors.black, Icons.tiktok),
      Platform2.youtube => (const Color(0xFFE5332A), Icons.play_arrow_rounded),
      Platform2.facebook => (const Color(0xFF1877F2), Icons.facebook),
      Platform2.x => (Colors.black, null),
      Platform2.other => (const Color(0xFF5B6270), Icons.link_rounded),
    };
    return Semantics(
      label: platform.label,
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: platform == Platform2.instagram
              ? const LinearGradient(colors: [Color(0xFFF58529), Color(0xFFDD2A7B), Color(0xFF8134AF)])
              : null,
          color: platform == Platform2.instagram ? null : color,
          border: Border.all(color: Colors.white, width: 1.5),
        ),
        child: icon != null
            ? Icon(icon, size: size * (platform == Platform2.youtube ? 0.7 : 0.55), color: Colors.white)
            : Text(
                'X',
                style: TextStyle(color: Colors.white, fontSize: size * 0.48, fontWeight: FontWeight.w900, height: 1),
              ),
      ),
    );
  }
}

/// How post images are loaded. Tests swap this to render without a network.
ImageProvider Function(String url) postImageProvider = kIsWeb
    // Covers come from other sites; let the browser show them as plain image
    // elements when it may not read their pixels.
    ? (url) => NetworkImage(url, webHtmlElementStrategy: WebHtmlElementStrategy.fallback)
    : CachedNetworkImageProvider.new;

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
    final tint = platform == null ? scheme.primary : platformColor(platform!);
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

/// Text that is cut to [lines] lines and, only when it does not fit, offers
/// "Show more". [ai] puts the sparkle in front that marks AI-written text.
class ExpandableText extends StatefulWidget {
  const ExpandableText(this.text, {super.key, this.style, this.lines = 2, this.ai = false});
  final String text;
  final TextStyle? style;
  final int lines;
  final bool ai;

  @override
  State<ExpandableText> createState() => _ExpandableTextState();
}

class _ExpandableTextState extends State<ExpandableText> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    final style = DefaultTextStyle.of(context).style.merge(widget.style);

    return LayoutBuilder(
      builder: (context, box) {
        // Measure with an em space standing in for the sparkle.
        final probe = TextPainter(
          text: TextSpan(text: '${widget.ai ? '\u2003 ' : ''}${widget.text}', style: style),
          maxLines: widget.lines,
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        )..layout(maxWidth: box.maxWidth);
        final overflows = probe.didExceedMaxLines;
        probe.dispose();

        final text = Text.rich(
          TextSpan(
            children: [
              if (widget.ai)
                WidgetSpan(
                  alignment: PlaceholderAlignment.middle,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Icon(Icons.auto_awesome_rounded, size: 13, color: accent, semanticLabel: 'AI description'),
                  ),
                ),
              TextSpan(text: widget.text),
            ],
          ),
          maxLines: _expanded ? null : widget.lines,
          overflow: _expanded ? TextOverflow.clip : TextOverflow.ellipsis,
          style: style,
        );
        if (!overflows && !_expanded) return text;

        return Semantics(
          button: true,
          label: _expanded ? 'Show less' : 'Show full text',
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _expanded = !_expanded),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AnimatedSize(
                  duration: const Duration(milliseconds: 160),
                  curve: Curves.easeOut,
                  alignment: Alignment.topLeft,
                  child: text,
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 3, bottom: 2),
                  child: Text(
                    _expanded ? 'Show less' : 'Show more',
                    style: theme.textTheme.labelSmall?.copyWith(color: accent, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
