# Vendored MisakiSwift

Source: https://github.com/mlalma/MisakiSwift (main, October 2026), Apache-2.0 (see `LICENSE`).
`MToken.swift` comes from https://github.com/mlalma/MLXUtilsLibrary 0.0.6, also Apache-2.0.

Local changes:

- Removed the MLX BART fallback network and the MLX / MLXUtilsLibrary dependencies.
  `EnglishG2P` takes an optional `fallback` closure for words missing from the lexicon instead.
- Fixed `EnglishNum2Word` dropping "twenty" from 21–29 (325 read as "three hundred five").
- Ships only the US English `us_gold.json` and `us_silver.json` lexicons.
