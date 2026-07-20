import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
import morning_brief as mb  # noqa: E402


class VttToText(unittest.TestCase):
    def test_strips_tags_and_dedups_rolling_lines(self):
        vtt = (
            "WEBVTT\nKind: captions\nLanguage: en\n\n"
            "00:00:00.000 --> 00:00:02.000\n"
            "hello <c>world</c>\n\n"
            "00:00:02.000 --> 00:00:04.000\n"
            "hello world\n"
            "second line\n"
        )
        self.assertEqual(mb.vtt_to_text(vtt), "hello world second line")

    def test_skips_numeric_cue_ids_and_notes(self):
        vtt = "WEBVTT\n\n1\n00:00:00.000 --> 00:00:01.000\ntext\nNOTE meta\n"
        self.assertEqual(mb.vtt_to_text(vtt), "text")


class SubjectSlug(unittest.TestCase):
    def test_replaces_separators(self):
        self.assertEqual(mb.subject_slug("AI/ML: news"), "AI-ML- news")

    def test_traversal_collapses_to_untitled(self):
        self.assertEqual(mb.subject_slug(".."), "untitled")
        self.assertEqual(mb.subject_slug("  "), "untitled")

    def test_newlines_removed(self):
        self.assertNotIn("\n", mb.subject_slug("a\nb"))


class SeenState(unittest.TestCase):
    def test_per_subject_keys(self):
        state = {"seen": {mb.seen_key("Tech", "vid1"): "t"}}
        self.assertTrue(mb.is_seen(state, "Tech", "vid1"))
        self.assertFalse(mb.is_seen(state, "Geo", "vid1"))

    def test_legacy_global_keys_still_recognized(self):
        state = {"seen": {"vid1": "t"}}  # pre-v1.0.1 format
        self.assertTrue(mb.is_seen(state, "Tech", "vid1"))
        self.assertTrue(mb.is_seen(state, "Geo", "vid1"))


class AppendIdempotency(unittest.TestCase):
    def test_already_written_sections_are_dropped(self):
        existing = "## Old\n[Watch on YouTube](https://www.youtube.com/watch?v=abc123DEF45)\n"
        sections = [
            {"id": "abc123DEF45", "text": "dup"},
            {"id": "zzz999ZZZ99", "text": "new"},
        ]
        kept = mb.filter_already_written(sections, existing)
        self.assertEqual([s["id"] for s in kept], ["zzz999ZZZ99"])


class ClaudeSandbox(unittest.TestCase):
    def test_hardening_flags_present(self):
        flags = mb.CLAUDE_SANDBOX_FLAGS
        self.assertIn("--strict-mcp-config", flags)
        self.assertIn("--no-session-persistence", flags)
        self.assertIn("--setting-sources", flags)
        self.assertIn("--disallowedTools", flags)


if __name__ == "__main__":
    unittest.main()
