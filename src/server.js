/**
 * OpenClaw Railway Health Check Server
 * Minimal server for Railway health checks only.
 */

import http from "node:http";

const PORT = Number.parseInt(process.env.PORT ?? "8080", 10);

const server = http.createServer((req, res) => {
  // Health check - Railway only needs 200 OK
  if (req.url === "/healthz" && req.method === "GET") {
    res.writeHead(200, {
      "Content-Type": "text/plain",
      "X-Content-Type-Options": "nosniff",
      "X-Frame-Options": "DENY",
    });
    res.end("OK");
    return;
  }

  // Everything else - minimal info
  res.writeHead(200, {
    "Content-Type": "text/plain",
    "X-Content-Type-Options": "nosniff",
    "X-Frame-Options": "DENY",
  });
  res.end("OpenClaw Railway\n\nSSH in to configure: railway ssh");
});

server.listen(PORT, "0.0.0.0", () => {
  console.log(`[openclaw] Health server on :${PORT}`);
});
