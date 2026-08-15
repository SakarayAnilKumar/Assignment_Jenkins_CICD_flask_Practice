#!/usr/bin/env bash
set -e

IMAGE_TAG=$1
MONGO_URI_VAL=$2

AWS_REGION="us-east-1"
ECR_URL="316412036553.dkr.ecr.us-east-1.amazonaws.com"
CONTAINER_NAME="student-registration"
IMAGE_FULL="${ECR_URL}/${CONTAINER_NAME}:${IMAGE_TAG}"

echo "===> Authenticating with ECR..."
aws ecr get-login-password --region "${AWS_REGION}" | docker login --username AWS --password-stdin "${ECR_URL}"

echo "===> Stopping previous container..."
docker stop "${CONTAINER_NAME}" || true
docker rm "${CONTAINER_NAME}" || true

echo "===> Pulling image: ${IMAGE_FULL}..."
docker pull "${IMAGE_FULL}"

echo "===> Running new container..."
docker run -d \
  --name "${CONTAINER_NAME}" \
  --restart unless-stopped \
  -p 5000:5000 \
  -e MONGO_URI="${MONGO_URI_VAL}" \
  "${IMAGE_FULL}"

echo "===> Deployment completed successfully!"