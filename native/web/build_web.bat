@echo off
rem Build navigateur : native/web/out/stockfish.js + stockfish.wasm (Emscripten de tools/bin/emsdk).
call "%~dp0..\..\tools\bin\emsdk\emsdk_env.bat" >nul
set SF=%~dp0..\thirdparty\stockfish\src
if not exist "%~dp0out" mkdir "%~dp0out"
set SRCS=
for %%f in ("%SF%\*.cpp") do (
  if /I not "%%~nxf"=="main.cpp" if /I not "%%~nxf"=="thread.cpp" if /I not "%%~nxf"=="uci.cpp" if /I not "%%~nxf"=="tt.cpp" call set SRCS=%%SRCS%% "%%f"
)
em++ -O3 -std=c++14 -DNDEBUG -DIS_64BIT -DUSE_POPCNT -DNO_PREFETCH -I"%SF%" %SRCS% "%SF%\syzygy\tbprobe.cpp" ^
  "%~dp0thread_web.cpp" "%~dp0tt_web.cpp" "%~dp0sf_web.cpp" -o "%~dp0out\stockfish.js" ^
  -sENVIRONMENT=worker -sALLOW_MEMORY_GROWTH=1 -sINITIAL_MEMORY=67108864 -sSTACK_SIZE=8388608 ^
  -sEXPORTED_FUNCTIONS=_sf_init,_sf_command -sEXPORTED_RUNTIME_METHODS=ccall %SFEXTRA% || exit /b 1
copy /y "%~dp0stockfish_worker.js" "%~dp0out\" >nul
