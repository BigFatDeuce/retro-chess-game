// Retro Chess — Stockfish 11 embedded as a GDExtension (GPLv3, see native/thirdparty/stockfish/Copying.txt).
#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/packed_string_array.hpp>
#include <godot_cpp/variant/string.hpp>

namespace retrochess {

// UCI engine running in its own thread inside the game process. Commands are sent as text
// ("position fen ... moves ...", "go movetime 500"), answers are collected line by line.
class StockfishEngine : public godot::RefCounted {
	GDCLASS(StockfishEngine, godot::RefCounted)

protected:
	static void _bind_methods();

public:
	bool start();
	void send(const godot::String &command);
	godot::PackedStringArray poll();
	bool is_running() const;
};

} // namespace retrochess
