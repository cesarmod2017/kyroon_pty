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
  State<TerminalAutoCopy> createState() => TerminalAutoCopyState();
}

class TerminalAutoCopyState extends State<TerminalAutoCopy> {
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

  /// Copies whatever is selected right now. Public so an explicit copy
  /// (Ctrl+Shift+C) can go through this same path — and get the same text and
  /// the same confirmation — instead of xterm's built-in copy action.
  ///
  /// Pass [force] for an explicit copy: it skips the "already copied this"
  /// guard, so pressing the shortcut always writes to the clipboard.
  Future<void> copySelection({bool force = false}) async {
    final selection = widget.controller.selection;
    if (selection == null) {
      // Nothing selected (a plain tap clears it) — the next identical selection
      // should copy again.
      _lastCopied = null;
      return;
    }

    final text = _cleanUp(readTerminalRange(widget.terminal, selection));
    if (text.isEmpty || (!force && text == _lastCopied)) return;
    _lastCopied = text;

    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;

    setState(() => _showCopied = true);
    _copiedTimer?.cancel();
    _copiedTimer = Timer(const Duration(milliseconds: 1100), () {
      if (mounted) setState(() => _showCopied = false);
    });
  }

  Future<void> _copySelection() => copySelection();

  /// Drops the padding the terminal grid adds to the right of each line, plus
  /// blank lines at either end of the selection, so a copied command pastes as
  /// typed. Leading whitespace is kept — it's the indentation of the code or
  /// output being copied.
  static String _cleanUp(String text) {
    final lines = text.split('\n').map((line) => line.trimRight()).toList();
    while (lines.isNotEmpty && lines.first.isEmpty) {
      lines.removeAt(0);
    }
    while (lines.isNotEmpty && lines.last.isEmpty) {
      lines.removeLast();
    }
    return lines.join('\n');
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

/// Reads [range] out of the terminal as text, **keeping blank columns**.
///
/// This is deliberately not `terminal.buffer.getText(range)`: that one skips
/// every cell whose codepoint is 0, and a cell is 0 whenever nothing was ever
/// printed into it. Full-screen CLIs lay text out by moving the cursor rather
/// than printing runs of spaces, so their gaps are exactly those never-written
/// cells — `getText` collapses them and you copy "I'llanalyzetheexample"
/// instead of "I'll analyze the example". A blank cell is a blank column on
/// screen, so it is copied as a space.
///
/// Otherwise this mirrors xterm's own walk: segment per line, and a newline
/// between lines except where a line is the soft-wrapped continuation of the
/// previous one.
String readTerminalRange(Terminal terminal, BufferRange range) {
  final buffer = terminal.buffer;
  final normalized = range.normalized;
  final out = StringBuffer();

  for (final segment in normalized.toSegments()) {
    if (segment.line < 0 || segment.line >= buffer.height) continue;
    final line = buffer.lines[segment.line];

    if (!(segment.line == normalized.begin.y ||
        segment.line == 0 ||
        line.isWrapped)) {
      out.write('\n');
    }

    final from = (segment.start == null || segment.start! < 0)
        ? 0
        : segment.start!;
    final to = (segment.end == null || segment.end! > line.length)
        ? line.length
        : segment.end!;

    for (var i = from; i < to; i++) {
      final codePoint = line.getCodePoint(i);
      if (codePoint != 0) {
        // A double-width glyph occupies two columns; skip it if the second one
        // falls outside the selection, as xterm does.
        if (i + line.getWidth(i) <= to) out.writeCharCode(codePoint);
        continue;
      }
      // Codepoint 0 is also the filler cell that sits under the right half of a
      // double-width glyph — that column is already covered by the glyph we
      // just wrote, so it must not become a space.
      final isWideCharFiller = i > 0 && line.getWidth(i - 1) == 2;
      if (!isWideCharFiller) out.write(' ');
    }
  }

  return out.toString();
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
