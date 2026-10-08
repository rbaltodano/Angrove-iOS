import argparse
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import build_reader_documents
from build_reader_documents import (
    gutenberg,
    marker_sections,
    numbered_sections,
    paragraphs,
    passage_map,
)


class ReaderDocumentTests(unittest.TestCase):
    def test_partial_export_keeps_previous_complete_bundle(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            backend = root / "backend"
            (backend / "corpus").mkdir(parents=True)
            (backend / "data/corpus/raw").mkdir(parents=True)
            (root / "Angrove-iOS/LocalGrounding").mkdir(parents=True)
            sources = [
                {"id": source, "title": source, "license_status": "confirmed_pd"}
                for source in ["short-work", "aristotle-metaphysics"]
            ]
            (backend / "corpus/sources.yaml").write_text(
                json.dumps({"sources": sources})
            )
            (backend / "data/corpus/raw/short-work.txt").write_text(
                "A complete short work."
            )
            (backend / "data/corpus/raw/aristotle-metaphysics.txt").write_text(
                "[Metaphysics/Book 1]\n\nOnly the first book."
            )
            (root / "Angrove-iOS/LocalGrounding/passages.json").write_text(
                json.dumps(
                    [
                        {
                            "sourceId": source["id"],
                            "chunkIndex": 0,
                            "text": "A passage.",
                        }
                        for source in sources
                    ]
                )
            )
            output = root / "reader"
            output.mkdir()
            original = output / "library-index.json"
            original.write_text("previous complete bundle")
            args = argparse.Namespace(
                backend=backend,
                output=output,
                cache=root / "cache",
                audit=root / "audit.json",
            )
            with (
                patch.object(build_reader_documents, "ROOT", root),
                self.assertRaises(ValueError),
            ):
                build_reader_documents.build(args)
            self.assertEqual(original.read_text(), "previous complete bundle")
            self.assertEqual(list(output.iterdir()), [original])

    def test_long_paragraph_is_not_cut_into_retrieval_fragments(self):
        text = "Beginning " + "word " * 600 + "end of the sentence."
        self.assertEqual(paragraphs(text), [text])

    def test_missing_books_fail_instead_of_exporting_partial_text(self):
        with self.assertRaises(ValueError):
            marker_sections(
                "[Metaphysics/Book 1]\n\nFirst book.", "aristotle-metaphysics"
            )
        with self.assertRaises(ValueError):
            numbered_sections("Book I.\n\nOnly first book.", r"^Book [IVX]+\.$", 10)

    def test_numeric_book_order_preserves_all_prose(self):
        text = "\n\n".join(
            f"[Metaphysics/Book {i}]\n\nText of book {i}."
            for i in sorted(range(1, 15), key=str)
        )
        sections = marker_sections(text, "aristotle-metaphysics")
        self.assertEqual(
            [title for title, _ in sections], [f"Book {i}" for i in range(1, 15)]
        )
        self.assertTrue(
            all(f"Text of book {i}." in body for i, (_, body) in enumerate(sections, 1))
        )

    def test_source_boundaries_exclude_distributor_material(self):
        text = "Website header\n*** START OF THE PROJECT GUTENBERG EBOOK TITLE ***\nOriginal prose.\n*** END OF THE PROJECT GUTENBERG EBOOK TITLE ***\nWebsite footer"
        self.assertEqual(gutenberg(text), "Original prose.")
        with self.assertRaises(ValueError):
            gutenberg("A table of contents with no complete edition.")

    def test_citations_map_by_prose_after_reader_order_changes(self):
        original = [
            {
                "chunkIndex": 400,
                "text": "One complete passage with enough distinct words to identify its original source.",
            }
        ]
        reader = [{"chunkIndex": 20, "text": original[0]["text"]}]
        self.assertEqual(passage_map(original, reader), {"400": 20})
        self.assertEqual(
            passage_map(original, [{"chunkIndex": 0, "text": "Unrelated text"}]), {}
        )


if __name__ == "__main__":
    unittest.main()
