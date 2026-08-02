import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:xterm/xterm.dart';

import 'theme.dart';

/// Copies the terminal selection to the clipboard as soon as the user finishes
/// selecting — the X11 / PuTTY "select = copy" behaviour, no Ctrl+Shift+C.
///
/// Wraps a [TerminalView] and watches raw pointer events instead of the
/// controller: [TerminalController] notifies on every drag update, so copying
/// there would hit the clipboard dozens of times per selection. A pointer-up is
/// exactly "the user let go", which is also when double-tap (word) and
/// triple-tap (line) selections are final.
///
/// The selection is left on screen after copying, and a short "Copiado" pill
/// confirms it happened.
class TerminalAutoCopy extends StatefulWidget {
  const TerminalAutoCopy({
    super.key,
    required this.terminal,
    required this.controller,
    required this.child,
  });

  final Terminal terminal;
  final TerminalController controller;

  /// The terminal view (or anything wrapping it) whose selection is copied.
  final Widget child;

  @override
  State<TerminalAutoCopy> createState() => _TerminalAutoCopyState();
}

class _TerminalAutoCopyState extends State<TerminalAutoCopy> {
  /// Last text written to the clipboard, so releasing the pointer again over an
  /// unchanged selection doesn't re-copy it.
  String? _lastCopied;

  bool _showCopied = false;
  Timer? _copiedTimer;

  @override
  void dispose() {
    _copiedTimer?.cancel();
    super.dispose();
  }

  Future<void> _copySelection() async {
    final selection = widget.controller.selection;
    if (selection == null) {
      // Nothing selected (a plain tap clears it) — the next identical selection
      // should copy again.
      _lastCopied = null;
      return;
    }

    final text = _trimLineEnds(widget.terminal.buffer.getText(selection));
    if (text.isEmpty || text == _lastCopied) return;
    _lastCopied = text;

    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;

    setState(() => _showCopied = true);
    _copiedTimer?.cancel();
    _copiedTimer = Timer(const Duration(milliseconds: 1100), () {
      if (mounted) setState(() => _showCopied = false);
    });
  }

  /// Drops the padding the terminal grid adds to the right of each line, so a
  /// copied command pastes as typed instead of trailing dozens of spaces.
  static String _trimLineEnds(String text) {
    return text.split('\n').map((line) => line.trimRight()).join('\n').trim();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: Listener(
            onPointerUp: (_) => _copySelection(),
            child: widget.child,
          ),
        ),
        Positioned(
          top: 10,
          right: 12,
          child: IgnorePointer(
            child: AnimatedOpacity(
              opacity: _showCopied ? 1 : 0,
              duration: const Duration(milliseconds: 150),
              child: const _CopiedPill(),
            ),
          ),
        ),
      ],
    );
  }
}

class _CopiedPill extends StatelessWidget {
  const _CopiedPill();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(AppRadius.full),
        border: Border.all(color: AppColors.borderStrong),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_rounded, size: 13, color: AppColors.success),
          SizedBox(width: 5),
          Text(
            'Copiado',
            style: TextStyle(
              color: AppColors.fgDim,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
