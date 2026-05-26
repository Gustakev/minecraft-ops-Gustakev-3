#!/bin/bash
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
S3_BUCKET="minecraft-world-767398024557"
POD=$(kubectl get pod -l app=minecraft -o jsonpath='{.items[0].metadata.name}')
kubectl exec "$POD" -- tar -czf /tmp/world-backup.tar.gz -C /data world
kubectl cp "$POD":/tmp/world-backup.tar.gz /tmp/world-backup.tar.gz
aws s3 cp /tmp/world-backup.tar.gz s3://$S3_BUCKET/world.tar.gz
echo "Backup done: $(date)"
