cmake_minimum_required(VERSION 3.17)
project(retrochess_ai CXX)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

set(GODOTCPP_TARGET "template_release" CACHE STRING "" FORCE)
add_subdirectory(thirdparty/godot-cpp)

file(GLOB SF_SOURCES thirdparty/stockfish/src/*.cpp thirdparty/stockfish/src/syzygy/*.cpp)
list(FILTER SF_SOURCES EXCLUDE REGEX ".*/main\.cpp$")

# Stockfish 11 is C++11/14 code (its clamp() clashes with std::clamp under C++17): own static library.
add_library(stockfish STATIC ${SF_SOURCES})
set_target_properties(stockfish PROPERTIES CXX_STANDARD 14)
target_include_directories(stockfish PUBLIC thirdparty/stockfish/src)
target_compile_definitions(stockfish PUBLIC NDEBUG)

add_library(retrochess_ai SHARED src/register_types.cpp src/stockfish_engine.cpp)
target_link_libraries(retrochess_ai PRIVATE godot::cpp stockfish)
if(ANDROID)
  target_compile_definitions(stockfish PUBLIC IS_64BIT NO_PREFETCH USE_POPCNT)
  target_compile_options(stockfish PRIVATE -O3)
  set(RC_SUFFIX "android.${ANDROID_ABI}")
elseif(MSVC)
  target_compile_definitions(stockfish PUBLIC USE_POPCNT _CRT_SECURE_NO_WARNINGS NOMINMAX)
  target_compile_options(stockfish PRIVATE /O2 /EHsc /W1)
  target_compile_options(retrochess_ai PRIVATE /EHsc)
  set(RC_SUFFIX "windows.x86_64")
endif()
set_target_properties(retrochess_ai PROPERTIES
  OUTPUT_NAME "retrochess_ai.${RC_SUFFIX}"
  PREFIX "lib"
  LIBRARY_OUTPUT_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/../game/bin"
  RUNTIME_OUTPUT_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/../game/bin"
  RUNTIME_OUTPUT_DIRECTORY_RELEASE "${CMAKE_CURRENT_SOURCE_DIR}/../game/bin"
  LIBRARY_OUTPUT_DIRECTORY_RELEASE "${CMAKE_CURRENT_SOURCE_DIR}/../game/bin")
