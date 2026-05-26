#!/bin/bash
set -e
exec > /var/log/cloud-init-minecraft.log 2>&1

echo "=== Installing dependencies ==="
apt-get update -y
apt-get install -y curl unzip

curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip
unzip -o /tmp/awscliv2.zip -d /tmp
/tmp/aws/install

echo "=== Installing k3s ==="
curl -sfL https://get.k3s.io | sh -

echo "=== Waiting for k3s to be ready ==="
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
until kubectl get nodes 2>/dev/null | grep -q " Ready"; do
  echo "Waiting for node..."
  sleep 5
done
echo "k3s is ready"

echo "=== Setting up kubeconfig for ubuntu user ==="
mkdir -p /home/ubuntu/.kube
cp /etc/rancher/k3s/k3s.yaml /home/ubuntu/.kube/config
chown -R ubuntu:ubuntu /home/ubuntu/.kube

echo "=== Creating ECR image pull secret ==="
ECR_PASSWORD=$(aws ecr get-login-password --region us-east-1)
kubectl create secret docker-registry ecr-secret \
  --docker-server=${ecr_registry} \
  --docker-username=AWS \
  --docker-password="$ECR_PASSWORD" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "=== Setting up ECR secret refresh ==="
cat > /usr/local/bin/refresh-ecr-secret.sh << 'SCRIPT'
#!/bin/bash
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
ECR_PASSWORD=$(aws ecr get-login-password --region us-east-1)
kubectl create secret docker-registry ecr-secret \
  --docker-server=${ecr_registry} \
  --docker-username=AWS \
  --docker-password="$ECR_PASSWORD" \
  --dry-run=client -o yaml | kubectl apply -f -
echo "ECR secret refreshed: $(date)"
SCRIPT
chmod +x /usr/local/bin/refresh-ecr-secret.sh
echo "0 */6 * * * root /usr/local/bin/refresh-ecr-secret.sh >> /var/log/ecr-refresh.log 2>&1" > /etc/cron.d/ecr-refresh

echo "=== Writing Kubernetes manifests ==="
mkdir -p /opt/minecraft-k8s

cat > /opt/minecraft-k8s/configmap.yaml << 'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: minecraft-config
data:
  EULA: "TRUE"
  MEMORY: "1G"
  MOTD: "${motd}"
  TYPE: "VANILLA"
EOF

cat > /opt/minecraft-k8s/pvc.yaml << 'EOF'
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: minecraft-world
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 5Gi
EOF

cat > /opt/minecraft-k8s/deployment.yaml << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: minecraft
spec:
  replicas: 1
  selector:
    matchLabels:
      app: minecraft
  template:
    metadata:
      labels:
        app: minecraft
    spec:
      imagePullSecrets:
        - name: ecr-secret
      containers:
        - name: minecraft
          image: ${image_name}:${image_tag}
          ports:
            - containerPort: 25565
          envFrom:
            - configMapRef:
                name: minecraft-config
          startupProbe:
            tcpSocket:
              port: 25565
            failureThreshold: 30
            periodSeconds: 10
          livenessProbe:
            tcpSocket:
              port: 25565
            periodSeconds: 30
            failureThreshold: 3
          readinessProbe:
            tcpSocket:
              port: 25565
            periodSeconds: 10
            failureThreshold: 3
          resources:
            requests:
              memory: "1Gi"
              cpu: "500m"
            limits:
              memory: "1536Mi"
              cpu: "1500m"
          volumeMounts:
            - name: world-data
              mountPath: /data
      volumes:
        - name: world-data
          persistentVolumeClaim:
            claimName: minecraft-world
EOF

cat > /opt/minecraft-k8s/service.yaml << 'EOF'
apiVersion: v1
kind: Service
metadata:
  name: minecraft
spec:
  type: LoadBalancer
  selector:
    app: minecraft
  ports:
    - port: 25565
      targetPort: 25565
      protocol: TCP
EOF

echo "=== Applying manifests ==="
kubectl apply -f /opt/minecraft-k8s/

echo "=== Setting up S3 backup ==="
cat > /usr/local/bin/minecraft-backup.sh << 'SCRIPT'
#!/bin/bash
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
S3_BUCKET="${s3_bucket}"
POD=$(kubectl get pod -l app=minecraft -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -z "$POD" ]; then
  echo "$(date): No minecraft pod found, skipping backup"
  exit 1
fi
kubectl exec "$POD" -- tar -czf /tmp/world-backup.tar.gz -C /data world
kubectl cp "$POD":/tmp/world-backup.tar.gz /tmp/world-backup.tar.gz
aws s3 cp /tmp/world-backup.tar.gz s3://$S3_BUCKET/world.tar.gz
echo "$(date): Backup complete"
SCRIPT
chmod +x /usr/local/bin/minecraft-backup.sh
echo "0 * * * * root /usr/local/bin/minecraft-backup.sh >> /var/log/minecraft-backup.log 2>&1" > /etc/cron.d/minecraft-backup

echo "=== Cloud-init complete ==="
