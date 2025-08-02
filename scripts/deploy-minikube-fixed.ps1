# Script PowerShell pour deployer les microservices NestJS sur Minikube avec Helm

Write-Host "Deploiement des microservices NestJS sur Minikube avec Helm" -ForegroundColor Green

# Verifier que Minikube est demarre
$minikubeStatus = minikube status 2>$null
if ($minikubeStatus -notmatch "Running") {
    Write-Host "Minikube n'est pas demarre. Demarrage de Minikube..." -ForegroundColor Yellow
    minikube start --driver=docker --memory=4096 --cpus=2
}

# Configurer l'environnement Docker pour utiliser celui de Minikube
Write-Host "Configuration de l'environnement Docker pour Minikube..." -ForegroundColor Blue
& minikube -p minikube docker-env --shell powershell | Invoke-Expression

# Construire les images Docker dans l'environnement Minikube
Write-Host "Construction des images Docker..." -ForegroundColor Blue

# Construire l'image pour le service products
Write-Host "Construction de l'image products..." -ForegroundColor Cyan
docker build -f Dockerfile --build-arg APP_NAME=products -t nestjs-microservice/products:latest .

# Construire l'image pour l'API Gateway
Write-Host "Construction de l'image api-gateway..." -ForegroundColor Cyan
docker build -f Dockerfile --build-arg APP_NAME=api-gateway -t nestjs-microservice/api-gateway:latest .

# Verifier que Helm est installe
if (!(Get-Command helm -ErrorAction SilentlyContinue)) {
    Write-Host "Helm n'est pas installe. Veuillez installer Helm d'abord." -ForegroundColor Red
    Write-Host "Visitez: https://helm.sh/docs/intro/install/" -ForegroundColor Yellow
    exit 1
}

# Ajouter le repository Nginx Ingress si l'ingress est active
Write-Host "Configuration de l'Ingress Controller..." -ForegroundColor Blue
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

# Installer l'Ingress Controller si necessaire
$ingressPods = kubectl get pods -n ingress-nginx 2>$null | Select-String "ingress-nginx-controller"
if (!$ingressPods) {
    Write-Host "Installation de l'Ingress Controller..." -ForegroundColor Cyan
    helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx `
        --namespace ingress-nginx `
        --create-namespace `
        --wait

    # Attendre que l'Ingress Controller soit pret
    kubectl wait --namespace ingress-nginx `
        --for=condition=ready pod `
        --selector=app.kubernetes.io/component=controller `
        --timeout=300s
}

# Deployer avec Helm
Write-Host "Deploiement avec Helm..." -ForegroundColor Green
helm upgrade --install nestjs-microservices ./helm/nestjs-microservices `
    --values ./helm/nestjs-microservices/values-minikube.yaml `
    --wait `
    --timeout=300s

# Attendre que tous les pods soient prets
Write-Host "Attente que tous les pods soient prets..." -ForegroundColor Yellow
kubectl wait --for=condition=ready pod -l app.kubernetes.io/instance=nestjs-microservices --timeout=300s

# Afficher le statut du deploiement
Write-Host "Statut du deploiement:" -ForegroundColor Blue
kubectl get pods -l app.kubernetes.io/instance=nestjs-microservices
kubectl get services -l app.kubernetes.io/instance=nestjs-microservices

# Obtenir l'URL d'acces
$minikubeIp = minikube ip
$nodePort = kubectl get service nestjs-microservices-api-gateway -o jsonpath='{.spec.ports[0].nodePort}'

Write-Host ""
Write-Host "Deploiement termine avec succes!" -ForegroundColor Green
Write-Host ""
Write-Host "URLs d'acces:" -ForegroundColor Cyan
Write-Host "   - API Gateway (NodePort): http://$minikubeIp`:$nodePort" -ForegroundColor White
Write-Host "   - API Gateway (Ingress): http://nestjs-microservices.local (ajoutez l'entree dans hosts)" -ForegroundColor White
Write-Host ""
Write-Host "Pour ajouter l'entree hosts sur Windows:" -ForegroundColor Yellow
Write-Host "   1. Ouvrez PowerShell en tant qu'administrateur" -ForegroundColor White
Write-Host "   2. Executez: Add-Content -Path C:\Windows\System32\drivers\etc\hosts -Value `"$minikubeIp nestjs-microservices.local`"" -ForegroundColor White
Write-Host ""
Write-Host "Commandes utiles:" -ForegroundColor Cyan
Write-Host "   - Voir les logs: kubectl logs -f deployment/nestjs-microservices-api-gateway" -ForegroundColor White
Write-Host "   - Voir les pods: kubectl get pods" -ForegroundColor White
Write-Host "   - Tunnel Minikube: minikube tunnel" -ForegroundColor White
Write-Host ""
