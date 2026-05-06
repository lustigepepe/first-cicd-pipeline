# cicd-demo-app

A minimal Node.js web server that displays its current deployed version.

## Run locally

```bash
node app/server.js
```

Open `http://localhost:3000`. The version shown is read from `app/version.txt`.

## Project layout

```
app/
  server.js      Node.js HTTP server
  package.json
  version.txt    Contains the current version string
scripts/
  ec2-userdata.sh  Bootstrap script for the server (Node.js + pm2)
```
