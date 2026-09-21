const http = require("node:http");
const fs = require("node:fs");
const path = require("node:path");
const root = __dirname;
const args = process.argv.slice(2),
  portIndex = args.indexOf("--port");
const port = Number(
  portIndex >= 0 ? args[portIndex + 1] : process.env.PORT || 5188,
);
const sharePreview = args.includes("--share");
const types = {
  ".html": "text/html; charset=utf-8",
  ".js": "text/javascript; charset=utf-8",
  ".css": "text/css; charset=utf-8",
  ".png": "image/png",
  ".webp": "image/webp",
  ".webm": "video/webm",
  ".woff2": "font/woff2",
  ".ttf": "font/ttf",
  ".json": "application/json; charset=utf-8",
};
http
  .createServer((req, res) => {
    try {
      const requestPath = decodeURIComponent(
        new URL(req.url, "http://localhost").pathname,
      );
      const file = path.resolve(
        root,
        "." + (requestPath === "/" ? "/index.html" : requestPath),
      );
      if (file !== root && !file.startsWith(root + path.sep)) {
        res.writeHead(403);
        return res.end("Forbidden");
      }
      const relative = path.relative(root, file).split(path.sep).join("/");
      if (sharePreview && relative !== "index.html" &&
          !/^(?:css|js|assets)\/(?!.*(?:^|\/)\.)[^\\]*\.(?:css|js|png|jpe?g|webp|gif|svg|ico|woff2?|ttf|mp4|webm)$/i.test(relative)) {
        res.writeHead(404);
        return res.end("Not found");
      }
      fs.stat(file, (err, stat) => {
        if (err || !stat.isFile()) {
          res.writeHead(404);
          return res.end("Not found");
        }
        res.writeHead(200, {
          "Content-Type":
            types[path.extname(file)] || "application/octet-stream",
          "Cache-Control": sharePreview ? "no-store" : "no-cache",
        });
        fs.createReadStream(file).pipe(res);
      });
    } catch {
      res.writeHead(400);
      res.end("Bad request");
    }
  })
  .listen(port, "127.0.0.1", () =>
    process.stdout.write("Rolling preview: http://127.0.0.1:" + port + "\n"),
  );
