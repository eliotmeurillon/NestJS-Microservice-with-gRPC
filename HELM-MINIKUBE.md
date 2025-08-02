# Déploiement NestJS Microservices avec Helm sur Minikube

Ce guide vous explique comment déployer vos microservices NestJS avec gRPC sur Minikube en utilisant Helm.

## Prérequis

### Outils requis

- [Minikube](https://minikube.sigs.k8s.io/docs/start/) - Pour l'environnement Kubernetes local
- [kubectl](https://kubernetes.io/docs/tasks/tools/) - CLI Kubernetes
- [Helm](https://helm.sh/docs/intro/install/) - Gestionnaire de packages Kubernetes
- [Docker](https://docs.docker.com/get-docker/) - Pour construire les images

### Installation sur Windows

```powershell
# Installer Minikube
winget install Kubernetes.minikube

# Installer kubectl
winget install Kubernetes.kubectl

# Installer Helm
winget install Helm.Helm

# Vérifier les installations
minikube version
kubectl version --client
helm version
```

## Structure du Chart Helm

```
helm/nestjs-microservices/
├── Chart.yaml                      # Métadonnées du chart
├── values.yaml                     # Valeurs par défaut
├── values-minikube.yaml            # Valeurs spécifiques à Minikube
└── templates/
    ├── _helpers.tpl                # Templates d'aide
    ├── configmap.yaml              # ConfigMap pour les fichiers proto
    ├── api-gateway-deployment.yaml # Déploiement API Gateway
    ├── api-gateway-service.yaml    # Service API Gateway
    ├── products-deployment.yaml    # Déploiement Products
    ├── products-service.yaml       # Service Products
    ├── ingress.yaml                # Ingress pour l'accès externe
    └── hpa.yaml                    # Horizontal Pod Autoscaler
```

## Déploiement Rapide

### Option 1: Script PowerShell (Windows)

```powershell
# Exécuter le script de déploiement
.\scripts\deploy-minikube.ps1
```

### Option 2: Déploiement Manuel

1. **Démarrer Minikube**

```powershell
minikube start --driver=docker --memory=4096 --cpus=2
```

2. **Configurer l'environnement Docker**

```powershell
& minikube -p minikube docker-env --shell powershell | Invoke-Expression
```

3. **Construire les images Docker**

```powershell
# Image Products
docker build -f Dockerfile --build-arg APP_NAME=products -t nestjs-microservice/products:latest .

# Image API Gateway
docker build -f Dockerfile --build-arg APP_NAME=api-gateway -t nestjs-microservice/api-gateway:latest .
```

4. **Installer l'Ingress Controller**

```powershell
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update
helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx --namespace ingress-nginx --create-namespace --wait
```

5. **Déployer avec Helm**

```powershell
helm upgrade --install nestjs-microservices ./helm/nestjs-microservices --values ./helm/nestjs-microservices/values-minikube.yaml --wait
```

## Configuration

### Valeurs importantes dans `values-minikube.yaml`

```yaml
# Images locales (pas de pull depuis un registry)
image:
  pullPolicy: Never

# Resources adaptées à Minikube
resources:
  requests:
    memory: '128Mi'
    cpu: '50m'
  limits:
    memory: '256Mi'
    cpu: '200m'

# Service API Gateway avec NodePort
apiGateway:
  service:
    type: NodePort
    nodePort: 30080

# Ingress activé
ingress:
  enabled: true
  className: 'nginx'
```

## Accès aux Services

### Via NodePort

```powershell
# Obtenir l'IP de Minikube
$minikubeIp = minikube ip

# Obtenir le port du service
$nodePort = kubectl get service nestjs-microservices-api-gateway -o jsonpath='{.spec.ports[0].nodePort}'

# URL d'accès
Write-Host "API Gateway: http://$minikubeIp:$nodePort"
```

### Via Ingress

1. **Ajouter l'entrée dans le fichier hosts**

```powershell
# En tant qu'administrateur
$minikubeIp = minikube ip
Add-Content -Path C:\Windows\System32\drivers\etc\hosts -Value "$minikubeIp nestjs-microservices.local"
```

2. **Accéder via le nom de domaine**

```
http://nestjs-microservices.local
```

## Monitoring et Debug

### Vérifier le statut des pods

```powershell
kubectl get pods -l app.kubernetes.io/instance=nestjs-microservices
```

### Voir les logs

```powershell
# Logs API Gateway
kubectl logs -f deployment/nestjs-microservices-api-gateway

# Logs Products service
kubectl logs -f deployment/nestjs-microservices-products
```

### Voir les services

```powershell
kubectl get services -l app.kubernetes.io/instance=nestjs-microservices
```

### Décrire un pod

```powershell
kubectl describe pod <nom-du-pod>
```

## Test des Services

### Via curl

```powershell
# Test de santé API Gateway
curl http://nestjs-microservices.local/

# Test via NodePort
$minikubeIp = minikube ip
$nodePort = kubectl get service nestjs-microservices-api-gateway -o jsonpath='{.spec.ports[0].nodePort}'
curl "http://$minikubeIp:$nodePort/"
```

### Via Postman ou navigateur

- Ouvrez votre navigateur
- Allez sur `http://nestjs-microservices.local` ou `http://<minikube-ip>:<node-port>`

## Mise à jour du Déploiement

### Après modification du code

```powershell
# 1. Reconstruire les images
& minikube -p minikube docker-env --shell powershell | Invoke-Expression
docker build -f Dockerfile --build-arg APP_NAME=products -t nestjs-microservice/products:latest .
docker build -f Dockerfile --build-arg APP_NAME=api-gateway -t nestjs-microservice/api-gateway:latest .

# 2. Redéployer
helm upgrade nestjs-microservices ./helm/nestjs-microservices --values ./helm/nestjs-microservices/values-minikube.yaml

# 3. Redémarrer les pods (pour forcer l'utilisation des nouvelles images)
kubectl rollout restart deployment/nestjs-microservices-products
kubectl rollout restart deployment/nestjs-microservices-api-gateway
```

## Nettoyage

### Script de nettoyage

```powershell
.\scripts\cleanup-minikube.ps1
```

### Nettoyage manuel

```powershell
# Supprimer le déploiement Helm
helm uninstall nestjs-microservices

# Supprimer l'Ingress Controller (optionnel)
helm uninstall ingress-nginx -n ingress-nginx
kubectl delete namespace ingress-nginx

# Supprimer les images Docker
& minikube -p minikube docker-env --shell powershell | Invoke-Expression
docker rmi nestjs-microservice/products:latest -f
docker rmi nestjs-microservice/api-gateway:latest -f

# Arrêter Minikube
minikube stop

# Supprimer Minikube (supprime tout)
minikube delete
```

## Troubleshooting

### Problèmes courants

1. **Images non trouvées**

   - Vérifiez que vous avez configuré l'environnement Docker : `& minikube -p minikube docker-env --shell powershell | Invoke-Expression`
   - Vérifiez que `pullPolicy: Never` est défini dans values-minikube.yaml

2. **Pods en état CrashLoopBackOff**

   - Vérifiez les logs : `kubectl logs <nom-du-pod>`
   - Vérifiez les variables d'environnement
   - Vérifiez que les fichiers proto sont correctement montés

3. **Ingress ne fonctionne pas**

   - Vérifiez que l'Ingress Controller est installé : `kubectl get pods -n ingress-nginx`
   - Vérifiez l'entrée hosts
   - Essayez le NodePort en alternative

4. **Services inaccessibles**
   - Vérifiez que Minikube tunnel est actif : `minikube tunnel`
   - Vérifiez les ports : `kubectl get services`

### Commandes de debug utiles

```powershell
# Statut général
kubectl get all -l app.kubernetes.io/instance=nestjs-microservices

# Events Kubernetes
kubectl get events --sort-by=.metadata.creationTimestamp

# Décrire les ressources
kubectl describe deployment nestjs-microservices-api-gateway
kubectl describe service nestjs-microservices-api-gateway

# Helm status
helm status nestjs-microservices

# Test de connectivité interne
kubectl run debug --image=busybox --rm -it --restart=Never -- nslookup nestjs-microservices-products
```

## Prochaines Étapes

- Configurer un registry Docker privé
- Ajouter des tests automatisés
- Configurer un pipeline CI/CD
- Ajouter la surveillance avec Prometheus/Grafana
- Configurer la sauvegarde et la restauration
