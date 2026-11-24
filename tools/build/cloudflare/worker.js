// Retro Chess on Cloudflare: the browser version's files (assets) and the rooms of online games (/api/...).
//
// A room is a Durable Object named by its code (6 characters, no look-alike letters). Two players: the host opens
// it (GET /api/host, WebSocket), the guest joins it with the code (GET /api/room/<CODE>, WebSocket). The room relays
// the moves, keeps them (a player who drops out comes back with the same token and gets the game where it stands),
// checks only whose turn it is (each game checks that the moves are legal, as it does its own), and handles
// resignation, the end of the game and the rematch (colours swapped). No clock. A room left alone for a day is
// forgotten.
//
// Messages (JSON), client -> room: move {uci, n}, resign, over, rematch, ping.
// Room -> client: room {code, you, state, board, opponent, moves, result, game}, move {uci, n},
// opponent {state: joined | left | back}, resign, rematch_ask, error {why: not_found | full | version | bad}, pong.

import { DurableObject } from "cloudflare:workers";

const ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
const CODE_LEN = 6;
const PROTOCOL = 1;
const FORGET_MS = 24 * 3600 * 1000;

function newCode() {
	const bytes = crypto.getRandomValues(new Uint8Array(CODE_LEN));
	let s = "";
	for (const b of bytes) s += ALPHABET[b % ALPHABET.length];
	return s;
}

function clip(s, n) {
	return String(s || "").slice(0, n);
}

export default {
	async fetch(req, env) {
		const url = new URL(req.url);
		if (url.pathname === "/api/host") {
			if (req.headers.get("Upgrade") !== "websocket") return new Response("WebSocket attendu", { status: 426 });
			// a free code: a room that is still in use answers 409 and another code is drawn
			for (let i = 0; i < 5; i++) {
				const code = newCode();
				const u = new URL(req.url);
				u.searchParams.set("code", code);
				u.searchParams.set("role", "host");
				const res = await env.ROOMS.get(env.ROOMS.idFromName(code)).fetch(new Request(u, req));
				if (res.status !== 409) return res;
			}
			return new Response("Aucun code libre", { status: 503 });
		}
		const m = url.pathname.match(/^\/api\/room\/([A-Za-z0-9]{6})$/);
		if (m) {
			if (req.headers.get("Upgrade") !== "websocket") return new Response("WebSocket attendu", { status: 426 });
			const code = m[1].toUpperCase();
			const u = new URL(req.url);
			u.searchParams.set("code", code);
			u.searchParams.set("role", "join");
			return env.ROOMS.get(env.ROOMS.idFromName(code)).fetch(new Request(u, req));
		}
		if (url.pathname.startsWith("/api/")) return new Response("Introuvable", { status: 404 });
		return env.ASSETS.fetch(req);
	},
};

export class Room extends DurableObject {
	constructor(ctx, env) {
		super(ctx, env);
		this.room = null; // loaded from storage on first use (the object may have slept)
	}

	async load() {
		if (this.room === null) this.room = (await this.ctx.storage.get("room")) || false;
		return this.room;
	}

	async save() {
		this.room.touched = Date.now();
		await this.ctx.storage.put("room", this.room);
		await this.ctx.storage.setAlarm(Date.now() + FORGET_MS);
	}

	async alarm() {
		if (this.ctx.getWebSockets().length === 0) {
			await this.ctx.storage.deleteAll();
			this.room = false;
		} else {
			await this.ctx.storage.setAlarm(Date.now() + FORGET_MS);
		}
	}

	async fetch(req) {
		const url = new URL(req.url);
		const q = url.searchParams;
		let room = await this.load();
		if (q.get("role") === "host" && room && Date.now() - room.touched < FORGET_MS) {
			return new Response(null, { status: 409 }); // code in use: the Worker draws another
		}
		const pair = new WebSocketPair();
		const [client, server] = Object.values(pair);
		const token = clip(q.get("token"), 64);
		const me = { token, name: clip(q.get("name"), 24) || "Joueur", avatar: clip(q.get("avatar"), 40) };
		const fail = (why) => {
			this.ctx.acceptWebSocket(server, ["refused"]);
			server.send(JSON.stringify({ t: "error", why }));
			server.close(4000 + ["not_found", "full", "version", "bad"].indexOf(why), why);
			return new Response(null, { status: 101, webSocket: client });
		};
		if (parseInt(q.get("v") || "0", 10) !== PROTOCOL) return fail("version");
		if (token.length < 8) return fail("bad");
		let back = false; // a player coming back to their seat
		if (q.get("role") === "host") {
			let side = q.get("side");
			if (side !== "white" && side !== "black") side = Math.random() < 0.5 ? "white" : "black";
			room = this.room = {
				code: q.get("code"), board: clip(q.get("board"), 24) || "prairie", seats: { [side]: me },
				moves: [], result: null, rematch: {}, game: 1, touched: Date.now(),
			};
		} else {
			if (!room) return fail("not_found");
			const seat = this.seatOf(token);
			back = seat !== null;
			if (!seat) {
				const free = ["white", "black"].find((s) => !room.seats[s]);
				if (!free) return fail("full");
				room.seats[free] = me;
			} else {
				room.seats[seat].name = me.name;
				room.seats[seat].avatar = me.avatar;
			}
		}
		// one connection per player: an older one (a dropped line) is closed
		for (const ws of this.ctx.getWebSockets(token)) {
			try { ws.close(1000, "replaced"); } catch (e) {}
		}
		this.ctx.acceptWebSocket(server, [token]);
		await this.save();
		const side = this.seatOf(token);
		const other = this.other(side);
		this.sendTo(token, this.state(side));
		if (other && room.seats[other]) {
			const ot = room.seats[other].token;
			this.sendTo(ot, this.state(other));
			this.sendTo(ot, { t: "opponent", state: back ? "back" : "joined" });
		}
		return new Response(null, { status: 101, webSocket: client });
	}

	seatOf(token) {
		for (const s of ["white", "black"]) if (this.room && this.room.seats[s] && this.room.seats[s].token === token) return s;
		return null;
	}

	other(side) {
		return side === "white" ? "black" : side === "black" ? "white" : null;
	}

	state(side) {
		const r = this.room;
		const o = r.seats[this.other(side)];
		return {
			t: "room", code: r.code, you: side, board: r.board, game: r.game,
			state: r.seats.white && r.seats.black ? "playing" : "waiting",
			opponent: o ? { name: o.name, avatar: o.avatar, online: this.ctx.getWebSockets(o.token).length > 0 } : null,
			moves: r.moves, result: r.result,
		};
	}

	sendTo(token, msg) {
		const s = JSON.stringify(msg);
		for (const ws of this.ctx.getWebSockets(token)) {
			try { ws.send(s); } catch (e) {}
		}
	}

	async webSocketMessage(ws, data) {
		const room = await this.load();
		const token = this.ctx.getTags(ws)[0];
		const side = room ? this.seatOf(token) : null;
		if (!side) return;
		let msg;
		try { msg = JSON.parse(data); } catch (e) { return; }
		const other = room.seats[this.other(side)];
		switch (msg.t) {
			case "ping":
				ws.send(JSON.stringify({ t: "pong" }));
				return;
			case "move": {
				const n = msg.n | 0;
				const uci = clip(msg.uci, 5);
				if (n < room.moves.length && room.moves[n] === uci) return; // sent again after a reconnection
				const turn = room.moves.length % 2 === 0 ? "white" : "black";
				if (room.result || !other || n !== room.moves.length || turn !== side || !/^[a-h][1-8][a-h][1-8][qrbn]?$/.test(uci)) {
					ws.send(JSON.stringify(this.state(side))); // out of step: the player gets the game as it stands
					return;
				}
				room.moves.push(uci);
				await this.save();
				this.sendTo(other.token, { t: "move", uci, n });
				return;
			}
			case "resign":
				if (room.result) return;
				room.result = { winner: this.other(side), why: "resign" };
				await this.save();
				if (other) this.sendTo(other.token, { t: "resign" });
				return;
			case "over":
				if (!room.result) {
					room.result = { why: "end" };
					await this.save();
				}
				return;
			case "rematch":
				if (!room.result || !other) return;
				room.rematch[side] = true;
				if (room.rematch.white && room.rematch.black) {
					room.seats = { white: room.seats.black, black: room.seats.white };
					room.moves = [];
					room.result = null;
					room.rematch = {};
					room.game += 1;
					await this.save();
					for (const s of ["white", "black"]) this.sendTo(room.seats[s].token, this.state(s));
				} else {
					await this.save();
					this.sendTo(other.token, { t: "rematch_ask" });
				}
				return;
		}
	}

	async webSocketClose(ws, code, reason) {
		// answer the player's closing frame: their game sees the line closed at once (it waits otherwise)
		try { ws.close(code === 1005 || code === 1006 ? 1000 : code, "bye"); } catch (e) {}
		const room = await this.load();
		const token = this.ctx.getTags(ws)[0];
		const side = room ? this.seatOf(token) : null;
		if (!side) return;
		// still connected elsewhere (a newer line replaced this one): nothing to tell
		if (this.ctx.getWebSockets(token).some((w) => w !== ws)) return;
		const other = room.seats[this.other(side)];
		if (other) this.sendTo(other.token, { t: "opponent", state: "left" });
	}

	async webSocketError(ws) {
		await this.webSocketClose(ws, 1011, "error");
	}
}
