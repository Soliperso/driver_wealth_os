/// The app's three ways of asking a driver for one value.
///
/// These grew up inside the settings screen and were private to it, which meant
/// the next screen that needed to edit a number had the choice of importing
/// nothing or copying everything. A second dialect of "type a value into a
/// sheet" is how two screens end up disagreeing about what a keyboard, a
/// validation error or a Done button looks like, so they live here instead.
library;

import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';

/// Asks for a line of text, refusing to close while [validator] objects.
Future<String?> showTextEditorSheet({
  required BuildContext context,
  required String title,
  required String initialValue,
  required Key fieldKey,
  required String? Function(String) validator,
  TextCapitalization textCapitalization = TextCapitalization.none,
}) => showModalBottomSheet<String>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (context) => _TextEditorSheet(
    title: title,
    initialValue: initialValue,
    fieldKey: fieldKey,
    validator: validator,
    textCapitalization: textCapitalization,
  ),
);

/// Asks for a number, refusing anything outside [min]..[max].
Future<double?> showNumberEditorSheet({
  required BuildContext context,
  required String title,
  required double initialValue,
  required Key fieldKey,
  required double min,
  required double max,
  required String rangeError,
  String? prefixText,
  String? suffixText,
}) => showModalBottomSheet<double>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (context) => _NumberEditorSheet(
    title: title,
    initialValue: initialValue,
    fieldKey: fieldKey,
    min: min,
    max: max,
    rangeError: rangeError,
    prefixText: prefixText,
    suffixText: suffixText,
  ),
);

/// Asks the driver to pick one of [values], with [current] ticked.
Future<T?> showChoiceSheet<T>({
  required BuildContext context,
  required String title,
  required T current,
  required List<T> values,
  required String Function(T) label,
}) => showModalBottomSheet<T>(
  context: context,
  showDragHandle: true,
  builder: (context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.only(bottom: Space.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Space.xl,
              Space.sm,
              Space.xl,
              Space.md,
            ),
            child: Text(title, style: Theme.of(context).textTheme.titleLarge),
          ),
          for (final value in values)
            ListTile(
              title: Text(label(value)),
              trailing: value == current
                  ? Icon(
                      Icons.check_circle_rounded,
                      color: Theme.of(context).colorScheme.primary,
                    )
                  : null,
              onTap: () => Navigator.of(context).pop(value),
            ),
        ],
      ),
    ),
  ),
);

/// A number as a driver would write it: no trailing zeroes, but enough decimals
/// that a small rate does not round away to nothing.
String plainNumber(double value) => value.toStringAsFixed(
  value.truncateToDouble() == value
      ? 0
      : value < 1
      ? 3
      : 1,
);

class _TextEditorSheet extends StatefulWidget {
  const _TextEditorSheet({
    required this.title,
    required this.initialValue,
    required this.fieldKey,
    required this.validator,
    required this.textCapitalization,
  });

  final String title;
  final String initialValue;
  final Key fieldKey;
  final String? Function(String) validator;
  final TextCapitalization textCapitalization;

  @override
  State<_TextEditorSheet> createState() => _TextEditorSheetState();
}

class _TextEditorSheetState extends State<_TextEditorSheet> {
  late final TextEditingController _controller;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final error = widget.validator(_controller.text);
    if (error != null) {
      setState(() => _errorText = error);
      return;
    }
    Navigator.of(context).pop(_controller.text);
  }

  @override
  Widget build(BuildContext context) => EditorSheet(
    title: widget.title,
    onDone: _submit,
    child: TextField(
      key: widget.fieldKey,
      controller: _controller,
      autofocus: true,
      textCapitalization: widget.textCapitalization,
      textInputAction: TextInputAction.done,
      decoration: InputDecoration(
        labelText: widget.title,
        errorText: _errorText,
      ),
      onSubmitted: (_) => _submit(),
    ),
  );
}

class _NumberEditorSheet extends StatefulWidget {
  const _NumberEditorSheet({
    required this.title,
    required this.initialValue,
    required this.fieldKey,
    required this.min,
    required this.max,
    required this.rangeError,
    this.prefixText,
    this.suffixText,
  });

  final String title;
  final double initialValue;
  final Key fieldKey;
  final double min;
  final double max;
  final String rangeError;
  final String? prefixText;
  final String? suffixText;

  @override
  State<_NumberEditorSheet> createState() => _NumberEditorSheetState();
}

class _NumberEditorSheetState extends State<_NumberEditorSheet> {
  late final TextEditingController _controller;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: plainNumber(widget.initialValue));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = double.tryParse(_controller.text.trim());
    if (value == null ||
        !value.isFinite ||
        value < widget.min ||
        value > widget.max) {
      setState(() => _errorText = widget.rangeError);
      return;
    }
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) => EditorSheet(
    title: widget.title,
    onDone: _submit,
    child: TextField(
      key: widget.fieldKey,
      controller: _controller,
      autofocus: true,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      textInputAction: TextInputAction.done,
      decoration: InputDecoration(
        labelText: widget.title,
        prefixText: widget.prefixText,
        suffixText: widget.suffixText,
        errorText: _errorText,
      ),
      onSubmitted: (_) => _submit(),
    ),
  );
}

/// The chrome every editor sheet shares: a title, the field, and a Done button
/// that stays above the keyboard.
class EditorSheet extends StatelessWidget {
  const EditorSheet({
    super.key,
    required this.title,
    required this.child,
    required this.onDone,
    this.doneLabel = 'Done',
  });

  final String title;
  final Widget child;
  final VoidCallback onDone;
  final String doneLabel;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      padding: EdgeInsets.fromLTRB(
        Space.xl,
        Space.sm,
        Space.xl,
        MediaQuery.viewInsetsOf(context).bottom + Space.xl,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: Space.lg),
          child,
          const SizedBox(height: Space.lg),
          FilledButton(
            // Named for settings because that is where it started and three
            // tests already tap it by this key. Renaming it would be churn in
            // exchange for nothing a driver can see.
            key: const ValueKey('settings-editor-done'),
            onPressed: onDone,
            child: Text(doneLabel),
          ),
        ],
      ),
    ),
  );
}
