import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'logo.dart';

/// Three screens shown once, on first launch. The share menu is how Stash is
/// used, and nobody finds that by exploring the app.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, required this.onDone});
  final VoidCallback onDone;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _pages = PageController();
  int _page = 0;

  static const _steps = [
    kIsWeb
        ? (
            Icons.add_link_rounded,
            'Paste a link',
            'Copy the link of a video or post from Instagram, TikTok, YouTube or any site, and add it to Stash.',
          )
        : (
            Icons.ios_share_rounded,
            'Share to Stash',
            'In Instagram, TikTok, YouTube or any app, tap Share on a video or post and choose Stash.',
          ),
    (
      Icons.auto_awesome_rounded,
      'It files itself',
      'Stash reads the post, writes a short description and picks a folder, or makes a new one. One tap on Save and you are back in your feed.',
    ),
    (
      Icons.notifications_active_outlined,
      'Come back to it',
      'Set a reminder, search by what a video was about, and tick things off as you watch them.',
    ),
  ];

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _next() {
    if (_page == _steps.length - 1) return widget.onDone();
    _pages.nextPage(duration: const Duration(milliseconds: 260), curve: Curves.easeOutCubic);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final last = _page == _steps.length - 1;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          child: Column(
            children: [
              Row(
                children: [
                  const StashLogo(size: 36),
                  const Spacer(),
                  if (!last) TextButton(onPressed: widget.onDone, child: const Text('Skip')),
                ],
              ),
              Expanded(
                child: PageView.builder(
                  controller: _pages,
                  itemCount: _steps.length,
                  onPageChanged: (i) => setState(() => _page = i),
                  itemBuilder: (context, i) {
                    final (icon, title, body) = _steps[i];
                    return Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 96,
                          height: 96,
                          decoration: BoxDecoration(
                            color: scheme.primaryContainer,
                            borderRadius: BorderRadius.circular(30),
                          ),
                          child: Icon(icon, size: 44, color: scheme.onPrimaryContainer),
                        ),
                        const SizedBox(height: 32),
                        Text(
                          title,
                          style: theme.textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          body,
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                            height: 1.45,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < _steps.length; i++)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      width: i == _page ? 22 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: i == _page ? scheme.primary : scheme.outlineVariant,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 24),
              FilledButton(onPressed: _next, child: Text(last ? 'Get started' : 'Next')),
            ],
          ),
        ),
      ),
    );
  }
}
