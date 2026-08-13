"""Compatibility entry point for the PySide6/Qt Quick application.

The former CustomTkinter implementation lived in this module.  Keeping the
public ``main`` import stable avoids breaking shortcuts and downstream code.
"""

from __future__ import annotations

import re

from .qt_app import Controller, main


class App:
    """Deprecated compatibility shim; new code should use ``Controller``."""

    def markdown_spans(self, text: str):
        pattern = re.compile(r"```(?:\n)?([\s\S]*?)(?:\n)?```|\*\*(.+?)\*\*|(?<!\*)\*([^*\n]+?)\*(?!\*)|`([^`\n]+?)`")
        spans, position = [], 0
        for match in pattern.finditer(text):
            if match.start() > position:
                spans.append((text[position:match.start()], None))
            if match.group(1) is not None:
                spans.append((match.group(1), "codeblock"))
            elif match.group(2) is not None:
                spans.append((match.group(2), "bold"))
            elif match.group(3) is not None:
                spans.append((match.group(3), "italic"))
            else:
                spans.append((match.group(4), "code"))
            position = match.end()
        if position < len(text):
            spans.append((text[position:], None))
        return spans


__all__ = ["App", "Controller", "main"]
