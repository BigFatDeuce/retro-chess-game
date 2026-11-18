@echo off
rem Build Android arm64 : game/bin/libretrochess_ai.android.arm64-v8a.so (NDK et CMake du SDK Android).
set SDK=%LOCALAPPDATA%\Android\Sdk
set NDK=%SDK%\ndk\29.0.14206865
set CM=%SDK%\cmake\3.31.6\bin
"%CM%\cmake.exe" -S "%~dp0." -B "%~dp0build\android" -G Ninja -DCMAKE_MAKE_PROGRAM="%CM%\ninja.exe" ^
  -DCMAKE_TOOLCHAIN_FILE="%NDK%\build\cmake\android.toolchain.cmake" -DANDROID_ABI=arm64-v8a ^
  -DANDROID_PLATFORM=android-24 -DCMAKE_BUILD_TYPE=Release || exit /b 1
"%CM%\cmake.exe" --build "%~dp0build\android" --config Release -j 16 || exit /b 1
