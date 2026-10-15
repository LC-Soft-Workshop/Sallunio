import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Dialog keyboard actions use the same callbacks and validation as its buttons.
class KeyboardDialog extends StatelessWidget {
  const KeyboardDialog({
    super.key,
    this.title,
    this.content,
    this.actions,
    this.contentPadding,
    this.insetPadding = const EdgeInsets.symmetric(
      horizontal: 40,
      vertical: 24,
    ),
    this.scrollable = false,
    this.actionsAlignment,
  });
  final Widget? title, content;
  final List<Widget>? actions;
  final EdgeInsetsGeometry? contentPadding;
  final EdgeInsets? insetPadding;
  final bool scrollable;
  final MainAxisAlignment? actionsAlignment;
  AlertDialog get dialog => AlertDialog(
    title: title,
    content: content,
    actions: actions,
    contentPadding: contentPadding,
    insetPadding: insetPadding,
    scrollable: scrollable,
    actionsAlignment: actionsAlignment,
  );

  @override
  Widget build(BuildContext context) {
    VoidCallback? submit;
    for (final action in actions ?? <Widget>[]) {
      if (action is FilledButton) submit = action.onPressed;
      if (action is ElevatedButton) submit = action.onPressed;
    }
    if (submit == null && actions?.length == 1) {
      final action = actions!.single;
      if (action is TextButton) submit = action.onPressed;
    }
    return FocusTraversalGroup(
      child: Focus(
        autofocus: true,
        onKeyEvent: (_, event) {
          if (event is! KeyDownEvent ||
              HardwareKeyboard.instance.isControlPressed ||
              HardwareKeyboard.instance.isAltPressed ||
              HardwareKeyboard.instance.isMetaPressed ||
              HardwareKeyboard.instance.isShiftPressed) {
            return KeyEventResult.ignored;
          }
          if (event.logicalKey == LogicalKeyboardKey.escape &&
              actions?.isNotEmpty == true) {
            Navigator.of(context).maybePop();
            return KeyEventResult.handled;
          }
          if (submit != null &&
              [
                LogicalKeyboardKey.enter,
                LogicalKeyboardKey.numpadEnter,
              ].contains(event.logicalKey)) {
            var interactive = false;
            FocusManager.instance.primaryFocus?.context?.visitAncestorElements((
              element,
            ) {
              if (element.widget is ButtonStyleButton ||
                  element.widget is DropdownButton) {
                interactive = true;
              }
              return !interactive;
            });
            if (interactive) return KeyEventResult.ignored;
            submit();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: dialog,
      ),
    );
  }
}
