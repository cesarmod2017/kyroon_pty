import 'package:flutter_test/flutter_test.dart';
import 'package:kyroon_pty_example/terminal_auto_copy.dart';
import 'package:xterm/xterm.dart';

/// Selects the first [width] columns of row [row].
BufferRange _row(int row, int width) =>
    BufferRangeLine(CellOffset(0, row), CellOffset(width - 1, row));

void main() {
  group('readTerminalRange', () {
    test('keeps gaps a CLI drew by moving the cursor, not printing spaces', () {
      final terminal = Terminal(maxLines: 100);
      // How a full-screen CLI lays out a line: print a word, jump the cursor to
      // the next column (CHA — `ESC [ n G`), print the next word. The columns in
      // between are never written, so their cells hold codepoint 0 — which is
      // exactly what xterm's own getText() drops.
      terminal.write("I'll");
      terminal.write('\x1b[7Ganalyze');
      terminal.write('\x1b[15Gthe');
      terminal.write('\x1b[19Gexample');
      terminal.write('\x1b[27Gproject.');

      final text = readTerminalRange(terminal, _row(0, terminal.viewWidth));

      expect(text.trimRight(), "I'll  analyze the example project.");
      // The regression this guards against:
      expect(text, isNot(contains("I'llanalyze")));
    });

    test('xterm getText is the broken baseline (why we have our own)', () {
      final terminal = Terminal(maxLines: 100);
      terminal.write("I'll");
      terminal.write('\x1b[7Ganalyze');

      expect(
        terminal.buffer.getText(_row(0, terminal.viewWidth)),
        "I'llanalyze",
      );
    });

    test('preserves leading indentation', () {
      final terminal = Terminal(maxLines: 100);
      terminal.write('\x1b[5Gindented');

      final text = readTerminalRange(terminal, _row(0, terminal.viewWidth));

      expect(text, startsWith('    indented'));
    });

    test('spaces the app actually printed survive', () {
      final terminal = Terminal(maxLines: 100);
      terminal.write('git commit -m "hello world"');

      final text = readTerminalRange(terminal, _row(0, terminal.viewWidth));

      expect(text.trimRight(), 'git commit -m "hello world"');
    });

    test('double-width glyphs do not gain a filler space', () {
      final terminal = Terminal(maxLines: 100);
      terminal.write('日本語 ok');

      final text = readTerminalRange(terminal, _row(0, terminal.viewWidth));

      expect(text.trimRight(), '日本語 ok');
    });

    test('joins soft-wrapped lines without a newline', () {
      final terminal = Terminal(maxLines: 100);
      // Fill past the right edge so xterm wraps the line itself.
      terminal.write('a' * (terminal.viewWidth + 5));

      final text = readTerminalRange(
        terminal,
        BufferRangeLine(
          const CellOffset(0, 0),
          CellOffset(terminal.viewWidth - 1, 1),
        ),
      );

      expect(text.trimRight(), 'a' * (terminal.viewWidth + 5));
    });
  });
}
