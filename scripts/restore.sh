#!/bin/bash
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
S3_BUCKET="minecraft-world-767398024557"

kubectl scale deployment minecraft --replicas=0
sleep 5

aws s3 cp s3://$S3_BUCKET/world.tar.gz /tmp/world-backup.tar.gz

kubectl run restore-helper --image=busybox --restart=Never \
  --overrides='{"spec":{"volumes":[{"name":"world","persistentVolumeClaim":{"claimName":"minecraft-world"}}],"containers":[{"name":"restore-helper","image":"busybox","command":["sleep","3600"],"volumeMounts":[{"name":"world","mountPath":"/data"}]}]}}'

kubectl wait --for=condition=Ready pod/restore-helper --timeout=60s
kubectl cp /tmp/world-backup.tar.gz restore-helper:/tmp/world-backup.tar.gz
kubectl exec restore-helper -- tar -xzf /tmp/world-backup.tar.gz -C /data
kubectl delete pod restore-helper

kubectl scale deployment minecraft --replicas=1
echo "Restore complete"
