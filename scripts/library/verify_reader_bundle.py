#!/usr/bin/env python3
"""Verify the exact complete-text resources in a source folder or built .app."""

import argparse
import hashlib
import json
from pathlib import Path


def covers(sections, lower, upper):
    next_index = lower
    for section in sections:
        if (
            section["lowerBound"] != next_index
            or section["upperBound"] < next_index
            or section["upperBound"] >= upper
        ):
            raise ValueError("Missing or overlapping reader section: " + section["id"])
        if section["children"]:
            covers(
                section["children"], section["lowerBound"], section["upperBound"] + 1
            )
        next_index = section["upperBound"] + 1
    if not sections or next_index != upper:
        raise ValueError("Uncovered reader paragraphs")


def verify(folder):
    index_path = next(iter(folder.rglob("library-index.json")), None)
    if index_path is None:
        raise ValueError("Complete Library index missing")
    index = json.loads(index_path.read_text())
    if (
        index["schemaVersion"] != 1
        or len(index["documents"]) != 37
        or len({d["id"] for d in index["documents"]}) != 37
    ):
        raise ValueError("Expected all 37 unique catalog editions")
    count = size = locations = 0
    for document in index["documents"]:
        path = index_path.parent / document["filename"]
        data = path.read_bytes()
        if hashlib.sha256(data).hexdigest() != document["sha256"]:
            raise ValueError("Edition hash mismatch: " + document["id"])
        paragraphs = json.loads(data)
        if len(paragraphs) != document["paragraphCount"]:
            raise ValueError("Paragraph count mismatch: " + document["id"])
        for i, paragraph in enumerate(paragraphs):
            if (
                paragraph["chunkIndex"] != i
                or paragraph["sourceId"] != document["id"]
                or not paragraph["text"].strip()
            ):
                raise ValueError("Invalid paragraph: " + document["id"])
        covers(document["sections"], 0, len(paragraphs))
        if any(
            i < 0 or i >= len(paragraphs)
            for i in document["retrievalLocations"].values()
        ):
            raise ValueError("Invalid citation location: " + document["id"])
        count += len(paragraphs)
        size += len(data)
        locations += len(document["retrievalLocations"])
    return {
        "documents": 37,
        "paragraphs": count,
        "mappedRetrievalPassages": locations,
        "textBytes": size,
    }


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("folder", type=Path)
    args = parser.parse_args()
    print(json.dumps(verify(args.folder), indent=2))
