# Lab — Your First CI/CD Pipeline with GitHub Actions

## What you will build

Every time you push a version tag (like `v1.2.0`) to GitHub, a pipeline will automatically SSH into your server and deploy the latest code. No manual steps, no FTP, no copy-paste.

By the end of this lab you will have:
- A live Node.js app running on an EC2 server
- A GitHub Actions pipeline that deploys on every tagged release
- Hands-on experience with GitHub Secrets, git tags, and SSH-based deployment

---

## Prerequisites

- An AWS account (Free Tier works)
- A GitHub account
- A terminal with `ssh` and `git` available

---

## Part 1 — Fork the repository

1. Go to the repository URL your instructor shared.
2. Click **Fork** in the top-right corner, then **Create fork**.
3. Clone your fork to your machine:

```bash
git clone https://github.com/<your-username>/cicd-demo-app.git
cd cicd-demo-app
```

The repo contains a small Node.js app in `app/`. It serves a single web page that shows the contents of `app/version.txt`. Your pipeline will update that file on every deploy.

---

## Part 2 — Launch an EC2 server

You will create a virtual machine on AWS that will host the app. All steps use the AWS Console in your browser.

### 2.1 Open the EC2 Console

1. Log in to [console.aws.amazon.com](https://console.aws.amazon.com).
2. In the search bar at the top type **EC2** and click the service.
3. Make sure you are in the region you want (top-right corner). Any region works — just stay consistent throughout the lab.
4. Click **Launch instance**.

### 2.2 Configure the instance

**Name and tags**
- Name: `cicd-lab-server`

**Application and OS Image**
- Click **Quick Start** → select **Amazon Linux**.
- In the dropdown below, choose **Amazon Linux 2023 AMI** (the one labelled *Free tier eligible*).

**Instance type**
- Select **t2.micro** (Free tier eligible).

**Key pair**
- Click **Create new key pair**.
- Name: `my-cicd-key`
- Key pair type: **RSA**
- Private key file format: **.pem**
- Click **Create key pair**. A file called `my-cicd-key.pem` will download automatically. **Keep this file — you cannot download it again.**
- Move it somewhere safe and restrict its permissions:

```bash
chmod 600 ~/Downloads/my-cicd-key.pem
```

**Network settings**
- Click **Edit** next to Network settings.
- Under **Firewall (security groups)**, choose **Create security group**.
- The default SSH rule (port 22) is already there. Change its **Source** from `0.0.0.0/0` to **My IP** — this allows only your machine to SSH in.
- Click **Add security group rule**:
  - Type: **Custom TCP**
  - Port range: `3000`
  - Source: `0.0.0.0/0`
  - Description: `Web app`

**Advanced details — User data**

Scroll down to **Advanced details** and expand it. Paste the contents of `scripts/ec2-userdata.sh` into the **User data** field. This script runs once on first boot and installs Node.js and pm2 on the server.

### 2.3 Launch and get the IP

1. Click **Launch instance**.
2. Click **View all instances**.
3. Wait until the **Instance state** column shows **Running** and **Status check** shows **2/2 checks passed** (refresh the page — this takes about 2 minutes).
4. Click on the instance ID to open its details.
5. Copy the **Public IPv4 address** — you will use this throughout the lab.

### 2.4 Verify SSH access

Wait about 90 seconds after the instance passes its checks (the userdata script is still running), then:

```bash
ssh -i ~/Downloads/my-cicd-key.pem ec2-user@<YOUR_PUBLIC_IP>
```

Once connected, check the tools are ready:

```bash
node --version
npm --version
pm2 --version
```

You should see version numbers for all three. Type `exit` to close the SSH session.

---

## Part 3 — Understand GitHub Secrets

Before adding anything, it helps to understand why secrets exist and what the private key is doing here.

### How SSH authentication works

When you connect to EC2 from your laptop, two things happen under the hood:

1. Your EC2 instance holds the **public key** — AWS uploaded it automatically when you selected your key pair during launch. Think of it as a padlock on the server's door.
2. Your `my-cicd-key.pem` file holds the **private key** — the only thing that can unlock that padlock.

In the pipeline, it is not your laptop connecting to EC2 — it is a **temporary virtual machine on GitHub's servers** (called a runner). That runner has no credentials by default. You need to give it the private key so it can authenticate with your server.

### Why not just paste the key into the workflow file?

The workflow file lives in your git repository, which is public (or at least shared). Pasting a private key there would expose it to anyone who can read the repo. GitHub Secrets solve this: you store the key once in GitHub's encrypted vault, and the runner receives it at runtime as an environment variable. The value never appears in your code or in the workflow logs — GitHub automatically replaces any accidental leak with `***`.

### Add the two secrets

1. Go to your GitHub repository → **Settings** tab.
2. In the left sidebar, click **Secrets and variables** → **Actions**.
3. Click **New repository secret**.

**Secret 1 — EC2_HOST**
- Name: `EC2_HOST`
- Secret: your EC2 public IP address (e.g. `63.184.114.65`)
- Click **Add secret**.

**Secret 2 — EC2_SSH_KEY**
- Click **New repository secret** again.
- Name: `EC2_SSH_KEY`
- Open a terminal and print your private key:

```bash
cat ~/Downloads/my-cicd-key.pem
```

- Copy the **entire output**, including the header and footer:

```
-----BEGIN RSA PRIVATE KEY-----
MIIEowIBAAKCAQEA...
...many lines...
-----END RSA PRIVATE KEY-----
```

- Paste it into the **Secret** field.
- Click **Add secret**.

You should now see both secrets listed. The values are hidden — that is intentional.

---

## Part 4 — Build the workflow file

This is the core of the lab. You will create the GitHub Actions workflow file step by step, understanding each part before adding the next.

Create the file and its parent directories:

```bash
mkdir -p .github/workflows
touch .github/workflows/deploy.yml
```

Open `deploy.yml` in your editor. You will add to it section by section.

---

### Step 4.1 — Name and trigger

Add this to the file:

```yaml
name: Deploy to EC2

on:
  push:
    tags:
      - "v*"
```

**What this does:**

`name` is just a label — it appears in the GitHub Actions tab.

`on` defines what event starts the workflow. Here you are saying: only run this workflow when a **tag** is pushed, and only if that tag starts with `v`. A regular push to `main` will not trigger it. This is intentional — you deploy deliberately by creating a release tag, not on every commit.

---

### Step 4.2 — Define the job

Append this below the trigger:

```yaml
jobs:
  deploy:
    name: SSH Deploy
    runs-on: ubuntu-latest
```

**What this does:**

A workflow is made of one or more **jobs**. Each job runs on a separate machine. `runs-on: ubuntu-latest` tells GitHub to provision a fresh Ubuntu virtual machine for this job. That machine will run all the steps you define next.

---

### Step 4.3 — Check out the code

Append this inside the job (indented under `runs-on`):

```yaml
    steps:
      - name: Checkout code
        uses: actions/checkout@v4
```

**What this does:**

`uses` runs a pre-built action from the GitHub Marketplace. `actions/checkout@v4` clones your repository onto the runner. Without this step, the runner starts empty — it does not have your files.

`@v4` is the version of the action. Pinning a version is good practice: if the action author releases a breaking change, your workflow stays stable.

---

### Step 4.4 — Extract the version from the tag

Append this as the next step:

```yaml
      - name: Set version from tag
        run: |
          TAG=${GITHUB_REF#refs/tags/}
          echo "Deploying version: $TAG"
          echo "$TAG" > app/version.txt
```

**What this does:**

`run` executes shell commands on the runner. `GITHUB_REF` is an environment variable GitHub provides automatically — when triggered by a tag push it looks like `refs/tags/v1.2.0`. The expression `${GITHUB_REF#refs/tags/}` strips the prefix, leaving just `v1.2.0`.

That version string is written into `app/version.txt`. When the file is copied to the server in the next step, the app will immediately display the new version.

---

### Step 4.5 — Copy files to the server

Append this as the next step:

```yaml
      - name: Copy files to EC2
        uses: appleboy/scp-action@v0.1.7
        with:
          host: ${{ secrets.EC2_HOST }}
          username: ec2-user
          key: ${{ secrets.EC2_SSH_KEY }}
          source: "app/"
          target: "~/cicd-app"
          strip_components: 1
```

**What this does:**

`appleboy/scp-action` is a community action that copies files over SCP (Secure Copy, which uses SSH). Notice `${{ secrets.EC2_HOST }}` and `${{ secrets.EC2_SSH_KEY }}` — this is how you reference the secrets you added in Part 3. GitHub injects their values at runtime.

`strip_components: 1` removes the leading `app/` folder prefix so files land directly in `~/cicd-app` on the server instead of `~/cicd-app/app/`.

---

### Step 4.6 — SSH in and restart the app

Append the final step:

```yaml
      - name: Restart app on EC2
        uses: appleboy/ssh-action@v1.0.3
        with:
          host: ${{ secrets.EC2_HOST }}
          username: ec2-user
          key: ${{ secrets.EC2_SSH_KEY }}
          script: |
            cd ~/cicd-app
            npm install --omit=dev
            pm2 restart cicd-app || pm2 start server.js --name cicd-app
            echo "Deployed $(cat version.txt)"
```

**What this does:**

`appleboy/ssh-action` opens an SSH session to your server and runs the `script` block. `npm install --omit=dev` ensures dependencies are up to date (skipping dev-only packages). `pm2 restart cicd-app || pm2 start server.js --name cicd-app` restarts the process if it is already running, or starts it fresh if this is the first deploy. pm2 keeps the app alive even if the SSH session closes.

---

### Your complete workflow file

Your `deploy.yml` should now look exactly like this:

```yaml
name: Deploy to EC2

on:
  push:
    tags:
      - "v*"

jobs:
  deploy:
    name: SSH Deploy
    runs-on: ubuntu-latest

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Set version from tag
        run: |
          TAG=${GITHUB_REF#refs/tags/}
          echo "Deploying version: $TAG"
          echo "$TAG" > app/version.txt

      - name: Copy files to EC2
        uses: appleboy/scp-action@v0.1.7
        with:
          host: ${{ secrets.EC2_HOST }}
          username: ec2-user
          key: ${{ secrets.EC2_SSH_KEY }}
          source: "app/"
          target: "~/cicd-app"
          strip_components: 1

      - name: Restart app on EC2
        uses: appleboy/ssh-action@v1.0.3
        with:
          host: ${{ secrets.EC2_HOST }}
          username: ec2-user
          key: ${{ secrets.EC2_SSH_KEY }}
          script: |
            cd ~/cicd-app
            npm install --omit=dev
            pm2 restart cicd-app || pm2 start server.js --name cicd-app
            echo "Deployed $(cat version.txt)"
```

---

## Part 5 — First deploy

### 5.1 Seed the server (one-time setup)

Before the pipeline runs, the app needs to exist on the server. Do this once from your terminal:

```bash
PUBLIC_IP=<YOUR_EC2_IP>

scp -i ~/Downloads/my-cicd-key.pem \
  app/server.js app/package.json \
  ec2-user@"$PUBLIC_IP":~/cicd-app/

ssh -i ~/Downloads/my-cicd-key.pem ec2-user@"$PUBLIC_IP" \
  "cd ~/cicd-app && echo 'v1.0.0' > version.txt && npm install --omit=dev && pm2 start server.js --name cicd-app"
```

Open `http://<YOUR_EC2_IP>:3000` in a browser. You should see the page showing **v1.0.0**.

### 5.2 Commit and tag

```bash
git add .github/workflows/deploy.yml
git commit -m "add deploy workflow"
git tag v1.0.0
git push origin main
git push origin v1.0.0
```

Go to your GitHub repository → **Actions** tab. You will see a workflow run appear with the name **Deploy to EC2**. Click it to see the steps execute in real time.

When it finishes, refresh your browser — the page still shows v1.0.0, which is correct. The pipeline ran and confirmed everything is in order.

---

## Part 6 — Ship a new version

Make a visible change to the app. Open `app/server.js` and find this line in the `<style>` block:

```
background: #f0f4f8;
```

Change it to:

```
background: #fef3c7;
```

Commit, tag, and push:

```bash
git add app/server.js
git commit -m "change background color"
git tag v1.1.0
git push origin main
git push origin v1.1.0
```

Watch the **Actions** tab. After about 30 seconds the workflow completes. Refresh your browser — the page shows **v1.1.0** with the new background color.

---

## Understanding version numbers

Version tags follow a convention called **Semantic Versioning** (SemVer):

```
v  1  .  0  .  0
   |     |     |
   |     |     patch — bug fixes only
   |     minor — new feature, no breaking changes
   major — breaking change
```

Using tags as the deploy trigger means:
- Every version that ever ran in production is permanently recorded in git history
- You can always check out exactly what was deployed at any point
- Rolling back means tagging an older commit and pushing the tag

---

## Stretch goals

**Add a syntax check step** — before copying files to the server, verify the app has no syntax errors. Add this step before the SCP step:

```yaml
      - name: Check syntax
        run: node --check app/server.js
```

**Handle failures** — add a step that only runs when the job fails:

```yaml
      - name: Notify on failure
        if: failure()
        run: echo "Deployment of ${{ github.ref_name }} failed!"
```

**Restrict to full semver tags** — change the trigger so only properly formatted tags (like `v1.2.3`) match, not arbitrary strings like `vtest`:

```yaml
on:
  push:
    tags:
      - "v[0-9]+.[0-9]+.[0-9]+"
```

---

## Cleanup

When you are done, terminate the instance to avoid charges.

In the EC2 Console:
1. Go to **Instances**.
2. Select your instance.
3. Click **Instance state** → **Terminate instance**.
4. Confirm.

Also delete the key pair (**Key Pairs** in the left sidebar → select → **Actions** → **Delete**) and the security group (**Security Groups** → select → **Actions** → **Delete security groups**).
