interface Env {
	DB: D1Database;
	HMAC_SECRET: string;
}

export default {
	async fetch(request: Request, env: Env): Promise<Response> {
		const url = new URL(request.url);

		if (request.method === "GET" && url.pathname === "/scores") {
			return handleGetScores(env);
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
	const expected = [...new Uint8Array(mac)]
		.map((b) => b.toString(16).padStart(2, "0"))
		.join("");
	return expected === signature;
}

async function hashIP(ip: string): Promise<string> {
	const data = new TextEncoder().encode(ip);
	const hash = await crypto.subtle.digest("SHA-256", data);
	return [...new Uint8Array(hash)]
		.map((b) => b.toString(16).padStart(2, "0"))
		.join("")
		.slice(0, 16);
}

// GET /scores — Top 50 leaderboard
async function handleGetScores(env: Env): Promise<Response> {
	const { results } = await env.DB.prepare(
		"SELECT id, game, player_name, score, link, created_at FROM scores WHERE game = 'gribli' ORDER BY score DESC LIMIT 50"
	).all();
	return json(results);
}

// POST /scores — Submit a score
async function handleSubmitScore(
	body: Record<string, unknown>,
	request: Request,
	env: Env
): Promise<Response> {
	const { player_name, score, link, device_id, timestamp } = body as {
		player_name?: string;
		score?: number;
		link?: string;
		device_id?: string;
		timestamp?: number;
	};

	if (!player_name || typeof score !== "number" || !device_id) {
		return json({ error: "Missing required fields" }, 400);
	}

	// Timestamp must be within ±2 minutes
	const now = Date.now();
	if (!timestamp || Math.abs(now - timestamp) > 120_000) {
		return json({ error: "Invalid timestamp" }, 400);
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

	// Only keep best score per device
	const existing = await env.DB.prepare(
		"SELECT id, score FROM scores WHERE device_id = ? AND game = 'gribli'"
	)
		.bind(device_id)
		.first<{ id: number; score: number }>();

	if (existing) {
		if (score <= existing.score) {
			return json({ success: true, updated: false });
		}
		await env.DB.prepare(
			"UPDATE scores SET player_name = ?, score = ?, link = ?, ip_hash = ?, created_at = strftime('%Y-%m-%dT%H:%M:%SZ', 'now') WHERE id = ?"
		)
			.bind(player_name, score, link || null, ipHash, existing.id)
			.run();
		return json({ success: true, updated: true });
	}

	await env.DB.prepare(
		"INSERT INTO scores (game, player_name, score, link, device_id, ip_hash) VALUES ('gribli', ?, ?, ?, ?, ?)"
	)
		.bind(player_name, score, link || null, device_id, ipHash)
		.run();

	return json({ success: true, updated: true }, 201);
}

// PUT /profile — Update player name/link on all scores
async function handleUpdateProfile(
	body: Record<string, unknown>,
	request: Request,
	env: Env
): Promise<Response> {
	const { player_name, link, device_id, timestamp } = body as {
		player_name?: string;
		link?: string;
		device_id?: string;
		timestamp?: number;
	};

	if (!player_name || !device_id) {
		return json({ error: "Missing required fields" }, 400);
	}

	const now = Date.now();
	if (!timestamp || Math.abs(now - timestamp) > 120_000) {
		return json({ error: "Invalid timestamp" }, 400);
	}

	await env.DB.prepare(
		"UPDATE scores SET player_name = ?, link = ? WHERE device_id = ?"
	)
		.bind(player_name, link || null, device_id)
		.run();

	return json({ success: true });
}
