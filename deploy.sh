#!/bin/bash

PUBLIC_IP=35.173.222.238
KEY_PATH="/Users/big_mac/awsIH/main-hagen01.pem"
APP_DIR="~/cicd-app"

echo "🔑 Testing SSH connection..."
ssh -i "$KEY_PATH" ec2-user@"$PUBLIC_IP" "echo '✅ SSH Connected!'"

if [ $? -ne 0 ]; then
  echo "❌ SSH connection failed"
  exit 1
fi

echo "📤 Copying files to EC2..."
scp -i "$KEY_PATH" app/server.js app/package.json ec2-user@"$PUBLIC_IP":"$APP_DIR"/

echo "🚀 Running deployment..."
ssh -i "$KEY_PATH" ec2-user@"$PUBLIC_IP" "
  mkdir -p $APP_DIR &&
  cd $APP_DIR &&
  echo 'v1.0.0' > version.txt &&
  npm install --omit=dev &&
  pm2 restart cicd-app --update-env || pm2 start server.js --name cicd-app
"

echo "🎉 Deployment finished!"
