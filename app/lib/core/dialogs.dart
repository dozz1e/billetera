import 'package:flutter/material.dart';

/// Consistent inset padding for form dialogs across the app: narrower than
/// AlertDialog's default (40 horizontal) so inputs, selects and buttons get
/// closer to the full screen width to lay out in.
const EdgeInsets kDialogInsetPadding = EdgeInsets.symmetric(
  horizontal: 20,
  vertical: 24,
);

/// Wraps dialog content so it claims the maximum width AlertDialog allows,
/// stretching every child (TextField, DropdownButtonFormField, buttons) to
/// that width instead of each sizing to its own intrinsic content width.
Widget wideDialogContent(List<Widget> children) {
  return SizedBox(
    width: double.maxFinite,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    ),
  );
}

/// A Cancelar/Guardar (or custom label) action row that splits the full
/// dialog width evenly between both buttons, replacing AlertDialog's default
/// right-aligned, content-sized action buttons.
Widget dialogActions({
  required VoidCallback? onCancel,
  required VoidCallback? onConfirm,
  String cancelLabel = 'Cancelar',
  String confirmLabel = 'Guardar',
  bool destructive = false,
}) {
  return Row(
    children: [
      Expanded(
        child: OutlinedButton(onPressed: onCancel, child: Text(cancelLabel)),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: destructive
            ? FilledButton.tonal(
                onPressed: onConfirm,
                style: FilledButton.styleFrom(
                  foregroundColor: Colors.white,
                  backgroundColor: Colors.red.shade600,
                ),
                child: Text(confirmLabel),
              )
            : FilledButton(onPressed: onConfirm, child: Text(confirmLabel)),
      ),
    ],
  );
}

/// Shows a destructive-action confirmation dialog. Returns true only if the
/// user explicitly confirmed.
Future<bool> confirmDelete(
  BuildContext context, {
  required String title,
  required String message,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      insetPadding: kDialogInsetPadding,
      title: Text(title),
      content: Text(message),
      actions: [
        dialogActions(
          onCancel: () => Navigator.pop(context, false),
          onConfirm: () => Navigator.pop(context, true),
          confirmLabel: 'Eliminar',
          destructive: true,
        ),
      ],
    ),
  );
  return confirmed ?? false;
}
