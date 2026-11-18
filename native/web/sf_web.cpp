// Retro Chess, version navigateur : Stockfish 11 en WebAssembly, dans un Web Worker (stockfish_worker.js).
// Le worker appelle sf_init() une fois, puis sf_command() pour chaque ligne UCI ; les réponses (cout) partent
// ligne par ligne vers la page par Module.print. Mêmes commandes que l'extension native : uci, isready,
// setoption, ucinewgame, position, go (depth / movetime), stop.
#include <emscripten/emscripten.h>

// uci.cpp est compilé ici (et pas à part) pour réutiliser ses fonctions internes position(), setoption(), go().
#include "../thirdparty/stockfish/src/uci.cpp"
#include "../thirdparty/stockfish/src/bitboard.h"
#include "../thirdparty/stockfish/src/endgame.h"
#include "../thirdparty/stockfish/src/tt.h"

namespace PSQT {
void init();
}

static Position g_pos;
static StateListPtr g_states;

extern "C" {

EMSCRIPTEN_KEEPALIVE void sf_init() {
	UCI::init(Options);
	PSQT::init();
	Bitboards::init();
	Position::init();
	Bitbases::init();
	Endgames::init();
	Threads.set(Options["Threads"]);
	Search::clear();
	g_states = StateListPtr(new std::deque<StateInfo>(1));
	g_pos.set(StartFEN, false, &g_states->back(), Threads.main());
}

EMSCRIPTEN_KEEPALIVE void sf_command(const char *line) {
	std::istringstream is(line);
	std::string token;
	is >> std::skipws >> token;
	if (token == "uci")
		sync_cout << "id name Stockfish 11\n" << Options << "\nuciok" << sync_endl;
	else if (token == "isready")
		sync_cout << "readyok" << sync_endl;
	else if (token == "setoption")
		setoption(is);
	else if (token == "ucinewgame")
		Search::clear();
	else if (token == "position")
		position(g_pos, is, g_states);
	else if (token == "go")
		go(g_pos, is, g_states);
	else if (token == "stop")
		Threads.stop = true;
	std::cout.flush();
}
}
