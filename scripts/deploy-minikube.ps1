# Script PowerShell pour deployer les microservices NestJS sur Minikube avec Helm

Write-Host "Deploiement des microservices NestJS sur Minikube avec Helm" -ForegroundColor Green

# Variables globales
$deployWithoutIngress = $false

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

    # Supprimer l'installation precedente si elle existe en etat d'erreur
    helm uninstall ingress-nginx -n ingress-nginx 2>$null
    kubectl delete namespace ingress-nginx 2>$null
    Start-Sleep -Seconds 10

    # Installer avec des parametres adaptes a Minikube
    helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx `
        --namespace ingress-nginx `
        --create-namespace `
        --set controller.service.type=NodePort `
        --set controller.admissionWebhooks.enabled=false `
        --set controller.admissionWebhooks.patch.enabled=false `
        --set controller.admissionWebhooks.createSecretJob.enabled=false `
        --set controller.admissionWebhooks.patchWebhookJob.enabled=false `
        --set controller.ingressClassResource.default=true `
        --wait `
        --timeout=600s

    # Attendre que l'Ingress Controller soit pret
    Write-Host "Attente que l'Ingress Controller soit pret..." -ForegroundColor Yellow
    kubectl wait --namespace ingress-nginx `
        --for=condition=ready pod `
        --selector=app.kubernetes.io/component=controller `
        --timeout=600s

    if ($LASTEXITCODE -ne 0) {
        Write-Host "L'Ingress Controller n'est pas devenu pret. Deploiement sans Ingress." -ForegroundColor Yellow
        $deployWithoutIngress = $true
    }
}
else {
    Write-Host "Ingress Controller deja present." -ForegroundColor Green
}

# Deployer avec Helm
Write-Host "Deploiement avec Helm..." -ForegroundColor Green

# Attendre un peu pour s'assurer que l'Ingress Controller est stable
if (!$deployWithoutIngress) {
    Start-Sleep -Seconds 30
}

# Determiner les arguments Helm
$helmArgs = @(
    "upgrade", "--install", "nestjs-microservices", "./helm/nestjs-microservices",
    "--values", "./helm/nestjs-microservices/values-minikube.yaml",
    "--wait",
    "--timeout=600s"
)

if ($deployWithoutIngress) {
    $helmArgs += "--set", "ingress.enabled=false"
    Write-Host "Deploiement sans Ingress..." -ForegroundColor Yellow
}

# Tentative de deploiement avec retry en cas d'erreur webhook
$maxRetries = 3
$retryCount = 0
$deploymentSuccess = $false

while ($retryCount -lt $maxRetries -and !$deploymentSuccess) {
    Write-Host "Tentative de deploiement $($retryCount + 1)/$maxRetries..." -ForegroundColor Cyan

    helm @helmArgs

    if ($LASTEXITCODE -eq 0) {
        $deploymentSuccess = $true
        Write-Host "Deploiement reussi!" -ForegroundColor Green
    }
    else {
        $retryCount++
        Write-Host "Echec de la tentative $retryCount. Code d'erreur: $LASTEXITCODE" -ForegroundColor Yellow

        if ($retryCount -lt $maxRetries) {
            Write-Host "Nouvelle tentative dans 30 secondes..." -ForegroundColor Yellow
            Start-Sleep -Seconds 30
        }
    }
}

if (!$deploymentSuccess) {
    Write-Host "Echec du deploiement apres $maxRetries tentatives." -ForegroundColor Red

    if (!$deployWithoutIngress) {
        Write-Host "Essayons de deployer sans ingress..." -ForegroundColor Yellow
        $deployWithoutIngress = $true

        # Deploiement sans ingress comme fallback
        helm upgrade --install nestjs-microservices ./helm/nestjs-microservices `
            --values ./helm/nestjs-microservices/values-minikube.yaml `
            --set ingress.enabled=false `
            --wait `
            --timeout=600s

        if ($LASTEXITCODE -eq 0) {
            $deploymentSuccess = $true
            Write-Host "Deploiement sans Ingress reussi!" -ForegroundColor Green
        }
        else {
            Write-Host "Echec definitif du deploiement. Code d'erreur: $LASTEXITCODE" -ForegroundColor Red
            exit 1
        }
    }
    else {
        Write-Host "Echec definitif du deploiement meme sans Ingress. Code d'erreur: $LASTEXITCODE" -ForegroundColor Red
        exit 1
    }
}

# Attendre que tous les pods soient prets
Write-Host "Attente que tous les pods soient prets..." -ForegroundColor Yellow
kubectl wait --for=condition=ready pod -l app.kubernetes.io/instance=nestjs-microservices --timeout=300s

if ($LASTEXITCODE -ne 0) {
    Write-Host "Certains pods ne sont pas devenus prets dans les temps. Diagnostic..." -ForegroundColor Yellow

    Write-Host "Statut des pods:" -ForegroundColor Blue
    kubectl get pods -l app.kubernetes.io/instance=nestjs-microservices

    Write-Host ""
    Write-Host "Logs de l'API Gateway (dernières 10 lignes):" -ForegroundColor Blue
    kubectl logs deployment/nestjs-microservices-api-gateway --tail=10 2>$null

    Write-Host ""
    Write-Host "Description du pod API Gateway:" -ForegroundColor Blue
    $apiGatewayPod = kubectl get pods -l app.kubernetes.io/component=api-gateway -o jsonpath='{.items[0].metadata.name}' 2>$null
    if ($apiGatewayPod) {
        kubectl describe pod $apiGatewayPod | Select-String -Pattern "Events:" -A 10
    }
}

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

if (!$deployWithoutIngress) {
    Write-Host "   - API Gateway (Ingress): http://nestjs-microservices.local (ajoutez l'entree dans hosts)" -ForegroundColor White
    Write-Host ""
    Write-Host "Pour ajouter l'entree hosts sur Windows:" -ForegroundColor Yellow
    Write-Host "   1. Ouvrez PowerShell en tant qu'administrateur" -ForegroundColor White
    Write-Host "   2. Executez: Add-Content -Path C:\Windows\System32\drivers\etc\hosts -Value `"$minikubeIp nestjs-microservices.local`"" -ForegroundColor White
}
else {
    Write-Host "   - Ingress desactive (utilisation du NodePort uniquement)" -ForegroundColor Yellow
}
Write-Host ""
Write-Host "Commandes utiles:" -ForegroundColor Cyan
Write-Host "   - Voir les logs: kubectl logs -f deployment/nestjs-microservices-api-gateway" -ForegroundColor White
Write-Host "   - Voir les pods: kubectl get pods" -ForegroundColor White
Write-Host "   - Tunnel Minikube: minikube tunnel" -ForegroundColor White
Write-Host ""
