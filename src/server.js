/**
 * OpenClaw Railway Health Check Server + SMS Webhook Proxy
 * Minimal server for Railway health checks and inbound SMS routing.
 */

import http from "node:http";
import { execSync } from "node:child_process";

const PORT = Number.parseInt(process.env.PORT ?? "8080", 10);

function isGatewayRunning() {
  try {
    execSync("pidof openclaw-gateway", { stdio: "ignore" });
    return true;
  } catch {
    return false;
  }
}

const server = http.createServer((req, res) => {
  // Health check
  if (req.url === "/healthz" && req.method === "GET") {
    const gatewayUp = isGatewayRunning();
    res.writeHead(gatewayUp ? 200 : 503, {
      "Content-Type": "text/plain",
      "X-Content-Type-Options": "nosniff",
      "X-Frame-Options": "DENY",
    });
    res.end(gatewayUp ? "OK" : "GATEWAY_DOWN");
    return;
  }

  // SMS webhook proxy — forward /sms/* to webhook on 3001
  if (req.url.startsWith("/sms/")) {
    const options = {
      hostname: "127.0.0.1",
      port: 3001,
      path: req.url,
      method: req.method,
      headers: req.headers,
    };
    const proxy = http.request(options, (proxyRes) => {
      res.writeHead(proxyRes.statusCode, proxyRes.headers);
      proxyRes.pipe(res);
    });
    proxy.on("error", () => {
      res.writeHead(502, { "Content-Type": "text/plain" });
      res.end("SMS webhook unavailable");
    });
    req.pipe(proxy);
    return;
  }

  // Everything else
  res.writeHead(200, {
    "Content-Type": "text/plain",
    "X-Content-Type-Options": "nosniff",
    "X-Frame-Options": "DENY",
  });
  res.end("OK");
});

server.listen(PORT, "0.0.0.0", () => {
  console.log(`[openclaw] Health server on :${PORT}`);
});
