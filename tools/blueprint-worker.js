/**
 * Cloudflare Worker for Storefront Blueprint Sharing
 *
 * Service: storefront-blueprint
 * Production URL: https://storefront-blueprint.ultimatejimmy.workers.dev
 *
 * Endpoints:
 *   - GET  / or /health               -> health check
 *   - POST / or /blueprint            -> upload blueprint JSON, returns { code, url, expires_at }
 *   - GET  /:code or /blueprint/:code -> fetch blueprint JSON by shortcode
 *
 * Bindings:
 *   - env.DB (Cloudflare D1 database)
 */

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, Authorization, Accept",
};

async function initSchema(db) {
  await db.prepare(`
    CREATE TABLE IF NOT EXISTS blueprints (
      code TEXT PRIMARY KEY,
      data TEXT NOT NULL,
      created_at INTEGER NOT NULL
    );
  `).run();
}

function generateCode(length = 6) {
  // Avoid visually ambiguous characters: 0/O, 1/I
  const chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
  let code = "";
  const array = new Uint8Array(length);
  crypto.getRandomValues(array);
  for (let i = 0; i < length; i++) {
    code += chars[array[i] % chars.length];
  }
  return code;
}

export default {
  async fetch(request, env) {
    if (request.method === "OPTIONS") {
      return new Response(null, { headers: corsHeaders });
    }

    const url = new URL(request.url);
    const db = env.DB;

    if (!db) {
      return new Response(
        JSON.stringify({ error: "Cloudflare D1 database binding 'DB' is not configured." }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    try {
      await initSchema(db);
    } catch (e) {
      // Schema initialization failover
    }

    const path = url.pathname.replace(/\/+$/, ""); // strip trailing slashes

    // GET / or /health
    if (request.method === "GET" && (path === "" || path === "/health")) {
      return new Response(
        JSON.stringify({ status: "ok", service: "storefront-blueprint" }),
        { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // POST / or /blueprint — Upload blueprint JSON
    if (request.method === "POST" && (path === "" || path === "/blueprint")) {
      let body;
      try {
        body = await request.text();
        if (!body || body.trim() === "") throw new Error("Empty body");
        const parsed = JSON.parse(body);
        if (typeof parsed !== "object" || parsed === null) {
          throw new Error("Payload must be a JSON object");
        }
      } catch (e) {
        return new Response(
          JSON.stringify({ error: "Invalid or empty JSON body: " + e.message }),
          { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }

      // Generate unique 6-character shortcode
      let code;
      let attempts = 0;
      while (attempts < 10) {
        code = generateCode(6);
        const existing = await db.prepare("SELECT code FROM blueprints WHERE code = ?").bind(code).first();
        if (!existing) break;
        attempts++;
      }

      const created_at = Math.floor(Date.now() / 1000);
      try {
        await db.prepare("INSERT INTO blueprints (code, data, created_at) VALUES (?, ?, ?)")
          .bind(code, body, created_at)
          .run();

        return new Response(
          JSON.stringify({
            code,
            url: `${url.origin}/blueprint/${code}`,
            expires_at: null,
          }),
          { status: 201, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      } catch (err) {
        return new Response(
          JSON.stringify({ error: "Failed to store blueprint: " + err.message }),
          { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }
    }

    // GET /:code or /blueprint/:code — Fetch blueprint JSON by shortcode
    const match = path.match(/^(?:\/blueprint)?\/([A-Za-z0-9]{4,12})$/);
    if (request.method === "GET" && match) {
      const code = match[1].toUpperCase();
      try {
        const row = await db.prepare("SELECT data FROM blueprints WHERE code = ?").bind(code).first();
        if (!row) {
          return new Response(
            JSON.stringify({ error: `Blueprint code '${code}' not found.` }),
            { status: 404, headers: { ...corsHeaders, "Content-Type": "application/json" } }
          );
        }

        return new Response(row.data, {
          status: 200,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      } catch (err) {
        return new Response(
          JSON.stringify({ error: "Database query failed: " + err.message }),
          { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }
    }

    return new Response(
      JSON.stringify({ error: `Route '${url.pathname}' not found.` }),
      { status: 404, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  },
};
