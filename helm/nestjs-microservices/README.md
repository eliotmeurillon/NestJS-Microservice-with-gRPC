# Chart Helm NestJS Microservices

Ce chart Helm permet de déployer l'architecture de microservices NestJS avec gRPC sur Kubernetes.

## Architecture

```
┌─────────────────┐    HTTP     ┌─────────────────┐    gRPC    ┌─────────────────┐
│   Client/User   │ ─────────▶  │   API Gateway   │ ─────────▶ │ Products Service │
└─────────────────┘             └─────────────────┘            └─────────────────┘
                                         │                              │
                                    Port 3000                      Port 5001
                                    (HTTP REST)                   (gRPC Protocol)
```

## Composants déployés

### Services

- **API Gateway** : Point d'entrée HTTP qui expose les APIs REST
- **Products Service** : Microservice gRPC pour la gestion des produits

### Resources Kubernetes

- **Deployments** : Gestion des pods applicatifs
- **Services** : Exposition des services à l'intérieur du cluster
- **ConfigMap** : Configuration des fichiers proto
- **Ingress** : Exposition externe via un contrôleur d'ingress
- **HPA** : Auto-scaling horizontal (optionnel)

## Prérequis

- Kubernetes cluster (Minikube, EKS, GKE, AKS, etc.)
- Helm 3.x
- kubectl configuré

## Installation rapide (Minikube)

```bash
# 1. Déploiement complet
npm run helm:deploy:minikube

# 2. Test du déploiement
npm run helm:test

# 3. Voir le statut
npm run k8s:status
```

## Installation manuelle

### 1. Préparer les images Docker

Pour Minikube :

```bash
# Configurer l'environnement Docker
& minikube -p minikube docker-env --shell powershell | Invoke-Expression

# Construire les images
docker build -f Dockerfile --build-arg APP_NAME=products -t nestjs-microservice/products:latest .
docker build -f Dockerfile --build-arg APP_NAME=api-gateway -t nestjs-microservice/api-gateway:latest .
```

### 2. Installer les dépendances

```bash
# Ajouter le repository Nginx Ingress
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

# Installer l'Ingress Controller
helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace \
  --wait
```

### 3. Déployer le chart

```bash
# Pour Minikube
helm upgrade --install nestjs-microservices ./helm/nestjs-microservices \
  --values ./helm/nestjs-microservices/values-minikube.yaml \
  --wait

# Pour Production
helm upgrade --install nestjs-microservices ./helm/nestjs-microservices \
  --values ./helm/nestjs-microservices/values-production.yaml \
  --wait
```

## Configuration

### Fichiers de valeurs

- `values.yaml` : Valeurs par défaut
- `values-minikube.yaml` : Configuration pour Minikube (développement)
- `values-production.yaml` : Configuration pour production

### Personnalisation des valeurs

```yaml
# Exemple de personnalisation
image:
  registry: 'your-registry.com/'
  repository: nestjs-microservice
  tag: 'v1.0.0'

apiGateway:
  replicaCount: 3
  resources:
    requests:
      memory: '512Mi'
      cpu: '200m'
    limits:
      memory: '1Gi'
      cpu: '1000m'

ingress:
  enabled: true
  hosts:
    - host: api.your-domain.com
```

## Accès aux services

### Minikube (NodePort)

```bash
# Obtenir l'URL d'accès
$minikubeIp = minikube ip
$nodePort = kubectl get service nestjs-microservices-api-gateway -o jsonpath='{.spec.ports[0].nodePort}'
echo "http://$minikubeIp:$nodePort"
```

### Production (Ingress)

```bash
# Via le nom de domaine configuré
curl https://api.your-domain.com
```

## Monitoring et Debug

### Voir les logs

```bash
# API Gateway
npm run k8s:logs:api-gateway

# Products Service
npm run k8s:logs:products
```

### Statut des ressources

```bash
npm run k8s:status
```

### Debug des pods

```bash
kubectl describe pod <pod-name>
kubectl get events --sort-by=.metadata.creationTimestamp
```

## Commandes utiles

### Validation du chart

```bash
npm run helm:validate
```

### Test du déploiement

```bash
npm run helm:test
```

### Nettoyage

```bash
npm run helm:cleanup:minikube
```

### Mise à jour

```bash
helm upgrade nestjs-microservices ./helm/nestjs-microservices \
  --values ./helm/nestjs-microservices/values-minikube.yaml
```

## Structure du chart

```
helm/nestjs-microservices/
├── Chart.yaml                      # Métadonnées du chart
├── values.yaml                     # Valeurs par défaut
├── values-minikube.yaml            # Configuration Minikube
├── values-production.yaml          # Configuration production
└── templates/
    ├── _helpers.tpl                # Templates d'aide
    ├── configmap.yaml              # ConfigMap proto files
    ├── api-gateway-deployment.yaml # Déploiement API Gateway
    ├── api-gateway-service.yaml    # Service API Gateway
    ├── products-deployment.yaml    # Déploiement Products
    ├── products-service.yaml       # Service Products
    ├── ingress.yaml                # Ingress pour accès externe
    └── hpa.yaml                    # Horizontal Pod Autoscaler
```

## Sécurité

### Contexte de sécurité

- Utilisateur non-root (UID 1001)
- Système de fichiers en lecture seule
- Capabilities minimales

### Secrets (Production)

```bash
# Créer un secret pour les variables sensibles
kubectl create secret generic nestjs-secrets \
  --from-literal=database-password=your-password
```

## Scalabilité

### Auto-scaling

```yaml
autoscaling:
  enabled: true
  minReplicas: 2
  maxReplicas: 10
  targetCPUUtilizationPercentage: 70
```

### Ressources

```yaml
resources:
  requests:
    memory: '256Mi'
    cpu: '100m'
  limits:
    memory: '512Mi'
    cpu: '500m'
```

## Troubleshooting

### Problèmes courants

1. **Images non trouvées**

   - Vérifiez `pullPolicy: Never` pour Minikube
   - Vérifiez que les images sont construites dans le bon registry

2. **Pods CrashLoopBackOff**

   - Vérifiez les logs : `kubectl logs <pod-name>`
   - Vérifiez la configuration des variables d'environnement

3. **Service inaccessible**

   - Vérifiez les services : `kubectl get services`
   - Vérifiez l'Ingress : `kubectl get ingress`

4. **Ingress ne fonctionne pas**
   - Vérifiez l'Ingress Controller : `kubectl get pods -n ingress-nginx`
   - Vérifiez la configuration DNS/hosts

### Logs de debug

```bash
# Logs de tous les composants
kubectl logs -l app.kubernetes.io/instance=nestjs-microservices --all-containers=true

# Events Kubernetes
kubectl get events --sort-by=.metadata.creationTimestamp

# Description détaillée
kubectl describe deployment nestjs-microservices-api-gateway
```
