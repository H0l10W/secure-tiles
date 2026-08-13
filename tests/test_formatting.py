import unittest

from secure_tiles.app import App


class FormattingTests(unittest.TestCase):
    def test_supported_markdown_spans(self):
        app = object.__new__(App)
        self.assertEqual(app.markdown_spans("**bold**"), [("bold", "bold")])
        self.assertEqual(app.markdown_spans("*italic*"), [("italic", "italic")])
        self.assertEqual(app.markdown_spans("`inline`"), [("inline", "code")])
        self.assertEqual(app.markdown_spans("```\nblock\n```"), [("block", "codeblock")])
        self.assertEqual(
            app.markdown_spans("plain **bold** and *italic*"),
            [("plain ", None), ("bold", "bold"), (" and ", None), ("italic", "italic")],
        )


if __name__ == "__main__":
    unittest.main()
