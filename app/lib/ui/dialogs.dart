import 'package:flutter/material.dart';

/// The app's popups, in one place so they all read the same way:
/// a title that asks one question, one line of consequence, and two buttons
/// of equal size where the coloured one is the action and the quiet one backs
/// out. Destructive actions are red.

class _Shell extends StatelessWidget {
  const _Shell({
    required this.title,
    this.message,
    this.icon,
    this.destructive = false,
    this.body,
    required this.actions,
  });
  final String title;
  final String? message;
  final IconData? icon;
  final bool destructive;
  final Widget? body;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final tone = destructive ? scheme.error : scheme.primary;
    return Dialog(
      backgroundColor: theme.bottomSheetTheme.backgroundColor,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (icon != null) ...[
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: tone.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(icon, color: tone, size: 24),
                ),
                const SizedBox(height: 16),
              ],
              Text(title, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
              if (message != null) ...[
                const SizedBox(height: 8),
                Text(
                  message!,
                  style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant, height: 1.45),
                ),
              ],
              if (body != null) ...[const SizedBox(height: 16), body!],
              const SizedBox(height: 24),
              Row(
                children: [
                  for (var i = 0; i < actions.length; i++) ...[
                    if (i > 0) const SizedBox(width: 12),
                    Expanded(child: actions[i]),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

ButtonStyle _quiet(BuildContext context) => FilledButton.styleFrom(
  minimumSize: const Size.fromHeight(50),
  backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
  foregroundColor: Theme.of(context).colorScheme.onSurface,
);

ButtonStyle _action(BuildContext context, bool destructive) {
  final scheme = Theme.of(context).colorScheme;
  return FilledButton.styleFrom(
    minimumSize: const Size.fromHeight(50),
    backgroundColor: destructive ? scheme.error : scheme.primary,
    foregroundColor: destructive ? scheme.onError : scheme.onPrimary,
  );
}

/// Asks a yes/no question. Returns true only when the action button is tapped.
Future<bool> confirm(
  BuildContext context, {
  required String title,
  String? message,
  required String confirmLabel,
  String cancelLabel = 'Cancel',
  IconData? icon,
  bool destructive = false,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => _Shell(
      title: title,
      message: message,
      icon: icon,
      destructive: destructive,
      actions: [
        FilledButton(style: _quiet(context), onPressed: () => Navigator.pop(context, false), child: Text(cancelLabel)),
        FilledButton(
          style: _action(context, destructive),
          onPressed: () => Navigator.pop(context, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return ok ?? false;
}

/// Asks for one piece of text. Returns null when cancelled. The action button
/// stays disabled while the field is empty, unless [allowEmpty].
Future<String?> promptText(
  BuildContext context, {
  required String title,
  String? message,
  String hint = '',
  String initial = '',
  String confirmLabel = 'Save',
  int maxLines = 1,
  bool allowEmpty = false,
  TextInputType? keyboardType,
  TextCapitalization capitalization = TextCapitalization.sentences,
}) => showDialog<String>(
  context: context,
  builder: (_) => _Prompt(
    title: title,
    message: message,
    hint: hint,
    initial: initial,
    confirmLabel: confirmLabel,
    maxLines: maxLines,
    allowEmpty: allowEmpty,
    keyboardType: keyboardType,
    capitalization: capitalization,
  ),
);

class _Prompt extends StatefulWidget {
  const _Prompt({
    required this.title,
    required this.message,
    required this.hint,
    required this.initial,
    required this.confirmLabel,
    required this.maxLines,
    required this.allowEmpty,
    required this.keyboardType,
    required this.capitalization,
  });
  final String title;
  final String? message;
  final String hint;
  final String initial;
  final String confirmLabel;
  final int maxLines;
  final bool allowEmpty;
  final TextInputType? keyboardType;
  final TextCapitalization capitalization;

  @override
  State<_Prompt> createState() => _PromptState();
}

class _PromptState extends State<_Prompt> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _ready => widget.allowEmpty || _controller.text.trim().isNotEmpty;

  void _submit() {
    if (_ready) Navigator.pop(context, _controller.text);
  }

  @override
  Widget build(BuildContext context) => _Shell(
    title: widget.title,
    message: widget.message,
    body: TextField(
      controller: _controller,
      autofocus: true,
      minLines: 1,
      maxLines: widget.maxLines,
      keyboardType: widget.keyboardType,
      autocorrect: widget.keyboardType != TextInputType.url,
      textCapitalization: widget.keyboardType == TextInputType.url ? TextCapitalization.none : widget.capitalization,
      textInputAction: widget.maxLines == 1 ? TextInputAction.done : TextInputAction.newline,
      onChanged: (_) => setState(() {}),
      onSubmitted: widget.maxLines == 1 ? (_) => _submit() : null,
      decoration: InputDecoration(hintText: widget.hint),
    ),
    actions: [
      FilledButton(style: _quiet(context), onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      FilledButton(
        style: _action(context, false),
        onPressed: _ready ? _submit : null,
        child: Text(widget.confirmLabel),
      ),
    ],
  );
}

/// One choice in [chooseOption].
class Option<T> {
  const Option(this.value, this.icon, this.label, this.detail, {this.destructive = false});
  final T value;
  final IconData icon;
  final String label;
  final String detail;
  final bool destructive;
}

/// A bottom sheet for decisions with more than two outcomes. Each option says
/// what it does in its own words, instead of three look-alike buttons.
Future<T?> chooseOption<T>(
  BuildContext context, {
  required String title,
  String? message,
  required List<Option<T>> options,
}) => showModalBottomSheet<T>(
  context: context,
  isScrollControlled: true,
  builder: (context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SheetHeader(title: title, subtitle: message, padding: EdgeInsets.zero),
            const SizedBox(height: 16),
            for (final o in options)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Material(
                  color: o.destructive ? scheme.error.withValues(alpha: 0.08) : scheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(18),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => Navigator.pop(context, o.value),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Icon(o.icon, color: o.destructive ? scheme.error : scheme.onSurface),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  o.label,
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: o.destructive ? scheme.error : null,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  o.detail,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                    height: 1.35,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ],
        ),
      ),
    );
  },
);

/// Title (and what it applies to) at the top of a bottom sheet.
class SheetHeader extends StatelessWidget {
  const SheetHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.padding = const EdgeInsets.fromLTRB(20, 0, 20, 8),
  });
  final String title;
  final String? subtitle;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle!,
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant, height: 1.4),
            ),
          ],
        ],
      ),
    );
  }
}
