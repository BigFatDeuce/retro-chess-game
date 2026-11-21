# IA native de Retro Chess

- `thirdparty/stockfish` : Stockfish 11 (GPLv3, voir `Copying.txt`), non modifié.
- `thirdparty/godot-cpp` : liaisons C++ de Godot (tag godot-4.5-stable, MIT).
- `src/` : extension `StockfishEngine` (GPLv3, comme Stockfish).

Le jeu lié à Stockfish relève de la GPLv3 : toute distribution doit fournir le code source complet.

Builds :
- Windows : `build_windows.bat` → `libretrochess_ai.windows.x86_64.dll` (Visual Studio, CMake).
- Android : `build_android.bat` → `libretrochess_ai.android.arm64-v8a.so` (NDK du SDK Android).
- Linux et macOS : `python build_cross.py` → `libretrochess_ai.linux.x86_64.so`, `libretrochess_ai.macos.x86_64.dylib`,
  `libretrochess_ai.macos.arm64.dylib` (compilés depuis Windows avec Zig, `tools/bin/zig`).
- Navigateur : `web/build_web.bat` → `web/out/stockfish.js` + `stockfish.wasm` + `stockfish_worker.js` (Emscripten).
  Stockfish tourne dans un Web Worker, sur un seul thread : `web/thread_web.cpp` et `web/tt_web.cpp` sont des copies
  de `thread.cpp` et `tt.cpp` sans threads ; `web/sf_web.cpp` reprend la boucle UCI de `uci.cpp`.
