const http = require("http");
const fs = require("fs");
const path = require("path");

const PORT = 3000;
const VERSION_FILE = path.join(__dirname, "version.txt");

function getVersion() {
  try {
    return fs.readFileSync(VERSION_FILE, "utf8").trim();
  } catch {
    return "unknown";
  }
}

const server = http.createServer((req, res) => {
  const version = getVersion();
  const html = `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <title>My App</title>
  <style>
    body { font-family: sans-serif; display: flex; justify-content: center;
           align-items: center; height: 100vh; margin: 0; background: red; }
    .card { background: white; padding: 2rem 3rem; border-radius: 12px;
            box-shadow: 0 4px 20px rgba(0,0,0,0.1); text-align: center; }
    h1 { color: #2d3748; margin-bottom: 0.5rem; }
    .version { font-size: 2rem; color: #48bb78; font-weight: bold; }
    .label { color: #718096; font-size: 0.9rem; margin-top: 0.5rem; }
  </style>
</head>
<body>
  <div class="card">
    <h1>My CI/CD App</h1>
    <div class="version">${version}</div>
    <div class="label">Current deployed version</div>
  </div>
</body>
</html>`;
  res.writeHead(200, { "Content-Type": "text/html" });
  res.end(html);
});

server.listen(PORT, () => {
  console.log(`Server running on port ${PORT} — version ${getVersion()}`);
});
