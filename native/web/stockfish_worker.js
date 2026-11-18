// Retro Chess, version navigateur : le moteur d'échecs (Stockfish 11, GPLv3) dans un Web Worker.
// La page envoie des lignes UCI (postMessage), le worker renvoie chaque ligne de réponse.
var queue = [];
var ready = false;
function sfRun(cmd) { Module.ccall('sf_command', null, ['string'], [cmd]); }
var Module = {
	print: function (line) { postMessage(line); },
	printErr: function () {},
	onRuntimeInitialized: function () {
		Module._sf_init();
		ready = true;
		for (var i = 0; i < queue.length; i++) sfRun(queue[i]);
		queue = [];
	}
};
onmessage = function (e) { if (ready) sfRun(e.data); else queue.push(e.data); };
importScripts('stockfish.js');
