# Complete Library reader (October 7, 2026)

The Library now reads complete edition documents with original paragraph boundaries, independently
of the frozen 51,836 retrieval chunks. All 37 catalog works have reader resources. Chapters and
books are ordered numerically; the Bible has book/chapter navigation in reading order.

The audit found incomplete upstream downloads: Gibbon was an index, Eusebius contained only Book I,
Westminster only chapters 1–9, Plutarch was a partial page enumeration, and the Tacitus entry omitted
the Histories. Complete editions replace those downloads for reading. Boethius and Adam Smith use
whole editions to avoid alphabetical poem ordering and duplicated volume/chapter text. The
Constitution includes its seven articles and all 27 amendments. Historical lost portions of Livy
and Tacitus are not invented; the reader identifies the surviving text. Schaff's creeds entry is
the complete Oecumenical Symbols section, rather than the entire multi-volume collection.

Sources, word counts, section lists and content hashes are recorded in
[Library-Completeness-Audit.json](Library-Completeness-Audit.json). Historical source spelling and
numbering are retained, including the Heidelberg edition's misprinted second question 73 (the
infant baptism question normally numbered 74). Website navigation and distributor notices are
excluded from reading text.

## Rebuild and verify

The generated `Angrove-iOS/LibraryDocuments/` directory is gitignored, like `LocalGrounding/`.
It is included by Xcode's synchronized app resource group. Install `beautifulsoup4` and `PyYAML`
in a tooling virtual environment, then run:

```sh
python scripts/library/build_reader_documents.py --backend ../Aquinas_Backend
python scripts/library/verify_reader_bundle.py Angrove-iOS/LibraryDocuments
python -m unittest discover -s scripts/library -p 'test_*.py'
```

The builder uses approved source texts in the backend's existing raw corpus, plus complete
public-domain edition downloads cached under `output/library-source-cache/`. Missing expected
books/chapters fail the export. The verifier checks all 37 edition hashes, paragraph identities,
contiguous section coverage and citation bounds; run it against the exact built `.app` as well.
The Swift reader also rejects invalid section coverage or missing resource files and shows an
unavailable state instead of silently substituting partial retrieval excerpts.

## Citation contract

`library-index.json` schema 1 lists each work's resource filename, edition context, section tree,
paragraph count and SHA-256. Each reader file contains ordered `LibraryPassage` paragraphs.
Their `chunkIndex` is a reader paragraph identifier, **not** a retrieval identifier.

`retrievalLocations` maps the existing retrieval chunk index to a reader paragraph by unchanged
prose. Persisted citations and the MiniLM embedding order are not rewritten. When removed page
chrome or a different translation has no matching prose, Read More opens the work without
highlighting an unrelated paragraph and the citation label remains the work title. New reader
text expands reading coverage; it does not expand semantic retrieval until that index is separately
rebuilt and validated.

The focused iOS `BundledLibraryReaderTests` checks all catalog editions, restored final chapters,
numeric ordering and a saved John 14 citation. Existing formatter and passage integration tests
cover scripture links and selection menus.
