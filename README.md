# Nexus Repository offline bundle (Kubernetes lab)

## Before beginning
- Kubernetes 1.37.1; F5 NGINX ingress class nginx-f5; cert-manager ClusterIssuer cluster-ca-issuer.
- Existing authenticated registry repo-sec.nexus.local:31920 accessible by cluster nodes.
- **IMPORTANT:** This manifest uses a single-node local PV on worker1 and is **lab-only**; not HA. It is not a safe design if this new Nexus is the only registry serving the cluster. Preserve the existing repo-sec registry separately.
- Validate the pinned `sonatype/nexus3:3.98.1` version and license/edition terms before deploying.

## 1. GitHub Actions download
Create a GitHub repository and commit `.github/workflows/nexus-offline.yml` to the default branch. Under Actions > Nexus 3 offline image bundle > Run workflow, run with image_tag `3.98.1`. Download the artifacts: `nexus-metadata` and each `nexus-part-*`. Each artifact is individually zipped by GitHub. Extract each part zip into a `parts/` folder and metadata zip into `metadata/`, alongside `scripts/`.

The workflow pulls an official `linux/amd64` image, records image metadata and SHA-256, gzips a Docker save, and splits it in 400MiB chunks. If more than 6 parts are generated, increase the upload steps in the workflow.

## 2. Transfer, validate, push
On a Docker-capable machine able to access the internal Nexus registry, run:

```bash
./scripts/reassemble-and-push.sh
```

It checks each part and the complete archive, runs docker load, then tags and pushes to `repo-sec.nexus.local:31920/sonatype/nexus3:3.98.1`. Ensure your Docker trust store accepts the registry certificate.

## 3. Prepare local persistent volume on worker1
Check that `/srv` has >=30GiB free. On worker1 only:

```bash
mkdir -p /srv/nexus-data
chown -R 200:200 /srv/nexus-data
chmod 750 /srv/nexus-data
```

For production, replace this static local PV with a robust StorageClass/PVC and backup strategy. Local PV data is tied to worker1. Do not delete this directory when recreating Pods.

## 4. Create image-pull credentials in the nexus namespace
```bash
kubectl create namespace nexus --dry-run=client -o yaml | kubectl apply -f -
# Create a scoped registry credential secret; avoid sharing the credentials.
kubectl -n nexus create secret docker-registry nexus-registry-secret \
  --docker-server=repo-sec.nexus.local:31920 \
  --docker-username='<registry-user>' \
  --docker-password='<registry-password>'
```

For production, prefer credential files/interactively entered secrets over command-line passwords visible in history/process lists.

## 5. Deploy
```bash
kubectl apply -f k8s/01-nexus.yaml
kubectl -n nexus get pvc,pod,svc,certificate,ingress
kubectl -n nexus rollout status deploy/nexus --timeout=900s
```

If the Pod can't pull, check image path, credentials, Nexus registry trust and `kubectl describe pod`. If PVC Pending, check local PV directory and `kubectl describe pvc`.

## 6. Client access
On the client's hosts file add `192.168.72.56 nexus.security.local` because NGINX Ingress is currently on master1 and its NodePort Service uses `externalTrafficPolicy: Local`.
Open https://nexus.security.local:30443/ . For browser trust, install the organization's trusted root CA in the client trust store. A TLS warning should not be ignored for actual administration.

Verify:
```bash
curl -vk --resolve nexus.security.local:30443:192.168.72.56 https://nexus.security.local:30443/
```

IMPORTANT: This HTTPS route is for the Nexus *web UI/API*. Docker registry clients often require additional connector configuration / a reachable 443 endpoint with a trusted cert, and cannot simply assume the Nexus UI Ingress enables Docker push/pull. Do not switch the cluster's image references to this new Nexus before independently testing registry connectors and migration.
