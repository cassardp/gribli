interface Env {
	DB: D1Database;
	HMAC_SECRET: string;
}

export default {
	async fetch(request: Request, env: Env): Promise<Response> {
		const url = new URL(request.url);

		if (request.method === "GET" && url.pathname === "/scores") {
			const game = url.searchParams.get("game") || "gribli";
			return handleGetScores(env, game);
		}

		// POST and PUT require valid HMAC signature
		if (request.method === "POST" || request.method === "PUT") {
			const signature = request.headers.get("X-Signature");
			const body = await request.text();
			if (!signature || !(await verifyHMAC(env.HMAC_SECRET, body, signature))) {
				return json({ error: "Unauthorized" }, 401);
			}
			const parsed = JSON.parse(body) as Record<string, unknown>;

			if (request.method === "POST" && url.pathname === "/scores") {
				return handleSubmitScore(parsed, request, env);
			}
			if (request.method === "PUT" && url.pathname === "/profile") {
				return handleUpdateProfile(parsed, request, env);
			}
		}

		return json({ error: "Not Found" }, 404);
	},
} satisfies ExportedHandler<Env>;

function json(data: unknown, status = 200): Response {
	return new Response(JSON.stringify(data), {
		status,
		headers: { "Content-Type": "application/json" },
	});
}

async function verifyHMAC(secret: string, body: string, signature: string): Promise<boolean> {
	const key = await crypto.subtle.importKey(
		"raw",
		new TextEncoder().encode(secret),
		{ name: "HMAC", hash: "SHA-256" },
		false,
		["sign"]
	);
	const mac = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(body));
	const expected = new TextEncoder().encode(
		[...new Uint8Array(mac)].map((b) => b.toString(16).padStart(2, "0")).join("")
	);
	const received = new TextEncoder().encode(signature);
	if (expected.byteLength !== received.byteLength) return false;
	return crypto.subtle.timingSafeEqual(expected, received);
}

async function hashIP(ip: string): Promise<string> {
	const data = new TextEncoder().encode(ip);
	const hash = await crypto.subtle.digest("SHA-256", data);
	return [...new Uint8Array(hash)]
		.map((b) => b.toString(16).padStart(2, "0"))
		.join("")
		.slice(0, 16);
}

// GET /scores — Rolling 30-day leaderboard
async function handleGetScores(env: Env, game: string): Promise<Response> {
	const cutoff = new Date(Date.now() - 30 * 24 * 60 * 60 * 1000);
	const cutoffISO = cutoff.toISOString().replace(".000Z", "Z");

	const { results } = await env.DB.prepare(
		"SELECT id, game, player_name, score, link, created_at FROM scores WHERE game = ? AND created_at >= ? ORDER BY score DESC LIMIT 99"
	).bind(game, cutoffISO).all();
	return json(results);
}

// POST /scores — Submit a score
async function handleSubmitScore(
	body: Record<string, unknown>,
	request: Request,
	env: Env
): Promise<Response> {
	const { player_name, score, link, device_id, timestamp, game: rawGame } = body as {
		player_name?: string;
		score?: number;
		link?: string;
		device_id?: string;
		timestamp?: number;
		game?: string;
	};

	const game = rawGame || "gribli";

	if (!player_name || typeof score !== "number" || !device_id) {
		return json({ error: "Missing required fields" }, 400);
	}

	const cleanName = player_name.replace(/<[^>]*>/g, "").trim();
	if (cleanName.length === 0 || cleanName.length > 20 || cleanName !== player_name.trim()) {
		return json({ error: "Invalid player name" }, 400);
	}

	if (!Number.isInteger(score) || score < 0) {
		return json({ error: "Invalid score" }, 400);
	}

	const normalizedLink = link && !/^https?:\/\//i.test(link) ? `https://${link}` : link;
	if (normalizedLink && !/^https?:\/\/.+/.test(normalizedLink)) {
		return json({ error: "Invalid link" }, 400);
	}

	// Timestamp must be within ±2 minutes
	const now = Date.now();
	if (!timestamp || Math.abs(now - timestamp) > 120_000) {
		return json({ error: "Invalid timestamp" }, 400);
	}

	// Check username uniqueness within game
	const nameTaken = await env.DB.prepare(
		"SELECT id FROM scores WHERE player_name = ? AND device_id != ? AND game = ? LIMIT 1"
	)
		.bind(player_name, device_id, game)
		.first();

	if (nameTaken) {
		return json({ error: "Username already taken" }, 409);
	}

	// Rate limit: 30s between submissions per device_id
	const lastByDevice = await env.DB.prepare(
		"SELECT created_at FROM scores WHERE device_id = ? ORDER BY created_at DESC LIMIT 1"
	)
		.bind(device_id)
		.first<{ created_at: string }>();

	if (lastByDevice) {
		const elapsed = now - new Date(lastByDevice.created_at).getTime();
		if (elapsed < 30_000) {
			return json({ error: "Too many requests" }, 429);
		}
	}

	// Rate limit: 10s between submissions per IP
	const ip = request.headers.get("CF-Connecting-IP") || "unknown";
	const ipHash = await hashIP(ip);

	const lastByIP = await env.DB.prepare(
		"SELECT created_at FROM scores WHERE ip_hash = ? ORDER BY created_at DESC LIMIT 1"
	)
		.bind(ipHash)
		.first<{ created_at: string }>();

	if (lastByIP) {
		const elapsed = now - new Date(lastByIP.created_at).getTime();
		if (elapsed < 10_000) {
			return json({ error: "Too many requests" }, 429);
		}
	}

	// Only keep best score per device per game within rolling 30 days
	const existing = await env.DB.prepare(
		"SELECT id, score, created_at FROM scores WHERE device_id = ? AND game = ?"
	)
		.bind(device_id, game)
		.first<{ id: number; score: number; created_at: string }>();

	if (existing) {
		const ageMs = now - new Date(existing.created_at).getTime();
		const within30Days = ageMs < 30 * 24 * 60 * 60 * 1000;

		if (within30Days && score <= existing.score) {
			return json({ success: true, updated: false });
		}

		await env.DB.prepare(
			"UPDATE scores SET player_name = ?, score = ?, link = ?, ip_hash = ?, created_at = strftime('%Y-%m-%dT%H:%M:%SZ', 'now') WHERE id = ?"
		)
			.bind(player_name, score, normalizedLink || null, ipHash, existing.id)
			.run();
		return json({ success: true, updated: true });
	}

	await env.DB.prepare(
		"INSERT INTO scores (game, player_name, score, link, device_id, ip_hash) VALUES (?, ?, ?, ?, ?, ?)"
	)
		.bind(game, player_name, score, normalizedLink || null, device_id, ipHash)
		.run();

	return json({ success: true, updated: true }, 201);
}

// PUT /profile — Update player name/link on all scores
async function handleUpdateProfile(
	body: Record<string, unknown>,
	request: Request,
	env: Env
): Promise<Response> {
	const { player_name, link, device_id, timestamp, game: rawGame } = body as {
		player_name?: string;
		link?: string;
		device_id?: string;
		timestamp?: number;
		game?: string;
	};

	const game = rawGame || "gribli";

	if (!player_name || !device_id) {
		return json({ error: "Missing required fields" }, 400);
	}

	const cleanName = player_name.replace(/<[^>]*>/g, "").trim();
	if (cleanName.length === 0 || cleanName.length > 20 || cleanName !== player_name.trim()) {
		return json({ error: "Invalid player name" }, 400);
	}

	const normalizedLink = link && !/^https?:\/\//i.test(link) ? `https://${link}` : link;
	if (normalizedLink && !/^https?:\/\/.+/.test(normalizedLink)) {
		return json({ error: "Invalid link" }, 400);
	}

	const now = Date.now();
	if (!timestamp || Math.abs(now - timestamp) > 120_000) {
		return json({ error: "Invalid timestamp" }, 400);
	}

	// Check username uniqueness within game
	const nameTaken = await env.DB.prepare(
		"SELECT id FROM scores WHERE player_name = ? AND device_id != ? AND game = ? LIMIT 1"
	)
		.bind(player_name, device_id, game)
		.first();

	if (nameTaken) {
		return json({ error: "Username already taken" }, 409);
	}

	await env.DB.prepare(
		"UPDATE scores SET player_name = ?, link = ? WHERE device_id = ? AND game = ?"
	)
		.bind(player_name, normalizedLink || null, device_id, game)
		.run();

	return json({ success: true });
}
