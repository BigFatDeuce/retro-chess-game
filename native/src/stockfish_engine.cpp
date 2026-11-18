// Retro Chess — Stockfish 11 embedded as a GDExtension (GPLv3).
// Stockfish's UCI loop reads std::cin and writes std::cout; both are redirected to in-memory
// line queues so the engine runs unchanged in a background thread (no external process: Android
// does not allow launching one from Godot).
#include "stockfish_engine.h"

#include <godot_cpp/core/class_db.hpp>

#include <condition_variable>
#include <deque>
#include <iostream>
#include <mutex>
#include <streambuf>
#include <string>
#include <thread>

#include "bitboard.h"
#include "endgame.h"
#include "position.h"
#include "search.h"
#include "thread.h"
#include "tt.h"
#include "uci.h"

namespace PSQT {
void init();
}

namespace {

// Blocking input: underflow() waits until a full command line is available.
class InputBuf : public std::streambuf {
	std::mutex m;
	std::condition_variable cv;
	std::deque<std::string> lines;
	std::string current;

public:
	void push(const std::string &line) {
		{
			std::lock_guard<std::mutex> lk(m);
			lines.push_back(line + "\n");
		}
		cv.notify_one();
	}

protected:
	int_type underflow() override {
		if (gptr() < egptr())
			return traits_type::to_int_type(*gptr());
		std::unique_lock<std::mutex> lk(m);
		cv.wait(lk, [this] { return !lines.empty(); });
		current = std::move(lines.front());
		lines.pop_front();
		char *b = current.data();
		setg(b, b, b + current.size());
		return traits_type::to_int_type(*gptr());
	}
};

// Output: complete lines are queued for the game to poll.
class OutputBuf : public std::streambuf {
	std::mutex m;
	std::string pending;
	std::deque<std::string> lines;

public:
	std::deque<std::string> take() {
		std::lock_guard<std::mutex> lk(m);
		std::deque<std::string> out;
		out.swap(lines);
		return out;
	}

protected:
	int_type overflow(int_type c) override {
		if (c == traits_type::eof())
			return traits_type::not_eof(c);
		std::lock_guard<std::mutex> lk(m);
		if (c == '\n') {
			lines.push_back(pending);
			pending.clear();
		} else if (c != '\r') {
			pending.push_back(char(c));
		}
		return c;
	}
	std::streamsize xsputn(const char *s, std::streamsize n) override {
		for (std::streamsize i = 0; i < n; ++i)
			overflow(traits_type::to_int_type(s[i]));
		return n;
	}
};

InputBuf g_in;
OutputBuf g_out;
std::thread g_thread;
std::mutex g_start_mutex;
bool g_running = false;

void engine_main() {
	UCI::init(Options);
	PSQT::init();
	Bitboards::init();
	Position::init();
	Bitbases::init();
	Endgames::init();
	Threads.set(Options["Threads"]);
	Search::clear();
	char arg0[] = "stockfish";
	char *argv[] = {arg0, nullptr};
	UCI::loop(1, argv);
	Threads.set(0);
}

} // namespace

namespace retrochess {

void StockfishEngine::_bind_methods() {
	godot::ClassDB::bind_method(godot::D_METHOD("start"), &StockfishEngine::start);
	godot::ClassDB::bind_method(godot::D_METHOD("send", "command"), &StockfishEngine::send);
	godot::ClassDB::bind_method(godot::D_METHOD("poll"), &StockfishEngine::poll);
	godot::ClassDB::bind_method(godot::D_METHOD("is_running"), &StockfishEngine::is_running);
}

bool StockfishEngine::start() {
	std::lock_guard<std::mutex> lk(g_start_mutex);
	if (g_running)
		return true;
	std::cin.rdbuf(&g_in);
	std::cout.rdbuf(&g_out);
	g_thread = std::thread(engine_main);
	g_thread.detach();
	g_running = true;
	return true;
}

void StockfishEngine::send(const godot::String &command) {
	if (!g_running)
		start();
	g_in.push(std::string(command.utf8().get_data()));
}

godot::PackedStringArray StockfishEngine::poll() {
	godot::PackedStringArray out;
	for (const std::string &l : g_out.take())
		out.push_back(godot::String::utf8(l.c_str()));
	return out;
}

bool StockfishEngine::is_running() const {
	return g_running;
}

} // namespace retrochess
