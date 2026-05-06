#!/bin/bash
# Runs on first boot (Amazon Linux 2023).
# Installs Node.js 18 and pm2, then creates the app directory.

set -e

dnf update -y
dnf install -y nodejs npm

npm install -g pm2

mkdir -p /home/ec2-user/cicd-app
chown ec2-user:ec2-user /home/ec2-user/cicd-app
echo "not-deployed-yet" > /home/ec2-user/cicd-app/version.txt
