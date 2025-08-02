# Script PowerShell ameliore pour deployer les microservices NestJS sur Minikube avec Helm

param(
    [switch]$CleanInstall,
    [switch]$SkipIngress,
    [int]$Timeout = 600
)

function Write-ColoredMessage {
    param($Message, $Color = "White")
    Write-Host $Message -ForegroundColor $Color
}

function Test-CommandExists {
    param($CommandName)
    return $null -ne (Get-Command $CommandName -ErrorAction SilentlyContinue)
}

function Wait-ForPods {
    param($Namespace = "default", $Selector, $TimeoutSeconds = 300)

    Write-ColoredMessage "Attente que les pods soient prets (timeout: $TimeoutSeconds secondes)..." "Yellow"

    try {
        kubectl wait --namespace $Namespace `
            --for=condition=ready pod `
            --selector=$Selector `
            --timeout="${TimeoutSeconds}s"
        return $true
    }
    catch {
        Write-ColoredMessage "Timeout atteint lors de l'attente des pods: $($_.Exception.Message)" "Red"
        return $false
    }
}

Write-ColoredMessage "Deploiement des microservices NestJS sur Minikube avec Helm" "Green"
Write-ColoredMessage "Options: CleanInstall=$CleanInstall, SkipIngress=$SkipIngress, Timeout=$Timeout" "Cyan"

# Verifications preliminaires
if (!(Test-CommandExists "minikube")) {
    Write-ColoredMessage "Minikube n'est pas installe ou n'est pas dans le PATH." "Red"
    exit 1
}

if (!(Test-CommandExists "kubectl")) {
    Write-ColoredMessage "kubectl n'est pas installe ou n'est pas dans le PATH." "Red"
    exit 1
}

if (!(Test-CommandExists "helm")) {
    Write-ColoredMessage "Helm n'est pas installe ou n'est pas dans le PATH." "Red"
    Write-ColoredMessage "Visitez: https://helm.sh/docs/intro/install/" "Yellow"
    exit 1
}

if (!(Test-CommandExists "docker")) {
    Write-ColoredMessage "Docker n'est pas installe ou n'est pas dans le PATH." "Red"
    exit 1
}

# Nettoyage si demande
if ($CleanInstall) {
    Write-ColoredMessage "Nettoyage des installations precedentes..." "Yellow"
    helm uninstall nestjs-microservices 2>$null
    helm uninstall ingress-nginx -n ingress-nginx 2>$null
    kubectl delete namespace ingress-nginx 2>$null
    Start-Sleep -Seconds 10
}

# Verifier que Minikube est demarre
Write-ColoredMessage "Verification du statut de Minikube..." "Blue"
$minikubeStatus = minikube status 2>$null
if ($minikubeStatus -notmatch "Running") {
    Write-ColoredMessage "Minikube n'est pas demarre. Demarrage de Minikube..." "Yellow"
    minikube start --driver=docker --memory=4096 --cpus=2

    if ($LASTEXITCODE -ne 0) {
        Write-ColoredMessage "Echec du demarrage de Minikube." "Red"
        exit 1
    }
}

# Configurer l'environnement Docker pour utiliser celui de Minikube
Write-ColoredMessage "Configuration de l'environnement Docker pour Minikube..." "Blue"
try {
    & minikube -p minikube docker-env --shell powershell | Invoke-Expression
}
catch {
    Write-ColoredMessage "Erreur lors de la configuration de l'environnement Docker: $($_.Exception.Message)" "Red"
    exit 1
}

# Construire les images Docker dans l'environnement Minikube
Write-ColoredMessage "Construction des images Docker..." "Blue"

# Construire l'image pour le service products
Write-ColoredMessage "Construction de l'image products..." "Cyan"
docker build -f Dockerfile --build-arg APP_NAME=products -t nestjs-microservice/products:latest .
if ($LASTEXITCODE -ne 0) {
    Write-ColoredMessage "Echec de la construction de l'image products." "Red"
    exit 1
}

# Construire l'image pour l'API Gateway
Write-ColoredMessage "Construction de l'image api-gateway..." "Cyan"
docker build -f Dockerfile --build-arg APP_NAME=api-gateway -t nestjs-microservice/api-gateway:latest .
if ($LASTEXITCODE -ne 0) {
    Write-ColoredMessage "Echec de la construction de l'image api-gateway." "Red"
    exit 1
}

# Configuration de l'Ingress Controller (si pas ignore)
if (!$SkipIngress) {
    Write-ColoredMessage "Configuration de l'Ingress Controller..." "Blue"

    # Ajouter le repository Nginx Ingress
    helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx 2>$null
    helm repo update

    # Verifier si l'Ingress Controller est deja installe et fonctionne
    $ingressPods = kubectl get pods -n ingress-nginx 2>$null | Select-String "ingress-nginx-controller.*Running"

    if (!$ingressPods) {
        Write-ColoredMessage "Installation de l'Ingress Controller..." "Cyan"

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
            --set controller.ingressClassResource.default=true `
            --set controller.service.nodePorts.http=30080 `
            --set controller.service.nodePorts.https=30443 `
            --wait `
            --timeout="${Timeout}s"

        if ($LASTEXITCODE -ne 0) {
            Write-ColoredMessage "Echec de l'installation de l'Ingress Controller." "Red"
            Write-ColoredMessage "Continuons sans Ingress..." "Yellow"
            $SkipIngress = $true
        }
        else {
            # Attendre que l'Ingress Controller soit pret
            $ingressReady = Wait-ForPods -Namespace "ingress-nginx" -Selector "app.kubernetes.io/component=controller" -TimeoutSeconds $Timeout
            if (!$ingressReady) {
                Write-ColoredMessage "L'Ingress Controller n'est pas devenu pret dans les temps. Continuons sans Ingress..." "Yellow"
                $SkipIngress = $true
            }
        }
    }
    else {
        Write-ColoredMessage "Ingress Controller deja installe et en cours d'execution." "Green"
    }
}

# Deployer avec Helm
Write-ColoredMessage "Deploiement avec Helm..." "Green"

# Determiner les valeurs a utiliser
$valuesFile = "./helm/nestjs-microservices/values-minikube.yaml"
$helmArgs = @(
    "upgrade", "--install", "nestjs-microservices", "./helm/nestjs-microservices",
    "--values", $valuesFile,
    "--wait",
    "--timeout", "${Timeout}s"
)

if ($SkipIngress) {
    $helmArgs += "--set", "ingress.enabled=false"
    Write-ColoredMessage "Deploiement sans Ingress..." "Yellow"
}

# Attendre un peu pour s'assurer que l'Ingress Controller est stable
if (!$SkipIngress) {
    Start-Sleep -Seconds 30
}

# Tentative de deploiement avec retry en cas d'erreur webhook
$maxRetries = 3
$retryCount = 0
$deploymentSuccess = $false

while ($retryCount -lt $maxRetries -and !$deploymentSuccess) {
    Write-ColoredMessage "Tentative de deploiement $($retryCount + 1)/$maxRetries..." "Cyan"

    helm @helmArgs

    if ($LASTEXITCODE -eq 0) {
        $deploymentSuccess = $true
        Write-ColoredMessage "Deploiement reussi!" "Green"
    }
    else {
        $retryCount++
        Write-ColoredMessage "Echec de la tentative $retryCount." "Yellow"

        if ($retryCount -lt $maxRetries) {
            Write-ColoredMessage "Nouvelle tentative dans 30 secondes..." "Yellow"
            Start-Sleep -Seconds 30
        }
    }
}

if (!$deploymentSuccess) {
    Write-ColoredMessage "Echec du deploiement apres $maxRetries tentatives." "Red"

    if (!$SkipIngress) {
        Write-ColoredMessage "Essayons de deployer sans ingress..." "Yellow"

        # Deploiement sans ingress comme fallback
        helm upgrade --install nestjs-microservices ./helm/nestjs-microservices `
            --values $valuesFile `
            --set ingress.enabled=false `
            --wait `
            --timeout="${Timeout}s"

        if ($LASTEXITCODE -eq 0) {
            $deploymentSuccess = $true
            $SkipIngress = $true
            Write-ColoredMessage "Deploiement sans Ingress reussi!" "Green"
        }
    }

    if (!$deploymentSuccess) {
        Write-ColoredMessage "Echec definitif du deploiement." "Red"
        exit 1
    }
}

# Attendre que tous les pods soient prets
Write-ColoredMessage "Attente que tous les pods soient prets..." "Yellow"
$podsReady = Wait-ForPods -Selector "app.kubernetes.io/instance=nestjs-microservices" -TimeoutSeconds $Timeout

if (!$podsReady) {
    Write-ColoredMessage "Certains pods ne sont pas devenus prets dans les temps." "Yellow"
    Write-ColoredMessage "Verification manuelle du statut..." "Cyan"
}

# Afficher le statut du deploiement
Write-ColoredMessage "Statut du deploiement:" "Blue"
kubectl get pods -l app.kubernetes.io/instance=nestjs-microservices
kubectl get services -l app.kubernetes.io/instance=nestjs-microservices

# Obtenir l'URL d'acces
$minikubeIp = minikube ip
$nodePort = kubectl get service nestjs-microservices-api-gateway -o jsonpath='{.spec.ports[0].nodePort}' 2>$null

Write-ColoredMessage ""
Write-ColoredMessage "Deploiement termine avec succes!" "Green"
Write-ColoredMessage ""
Write-ColoredMessage "URLs d'acces:" "Cyan"

if ($nodePort) {
    Write-ColoredMessage "   - API Gateway (NodePort): http://$minikubeIp`:$nodePort" "White"
}

if (!$SkipIngress) {
    Write-ColoredMessage "   - API Gateway (Ingress): http://nestjs-microservices.local" "White"
    Write-ColoredMessage ""
    Write-ColoredMessage "Pour ajouter l'entree hosts sur Windows:" "Yellow"
    Write-ColoredMessage "   1. Ouvrez PowerShell en tant qu'administrateur" "White"
    Write-ColoredMessage "   2. Executez: Add-Content -Path C:\Windows\System32\drivers\etc\hosts -Value `"$minikubeIp nestjs-microservices.local`"" "White"
}

Write-ColoredMessage ""
Write-ColoredMessage "Commandes utiles:" "Cyan"
Write-ColoredMessage "   - Voir les logs API Gateway: kubectl logs -f deployment/nestjs-microservices-api-gateway" "White"
Write-ColoredMessage "   - Voir les logs Products: kubectl logs -f deployment/nestjs-microservices-products" "White"
Write-ColoredMessage "   - Voir les pods: kubectl get pods" "White"
Write-ColoredMessage "   - Tunnel Minikube: minikube tunnel" "White"
Write-ColoredMessage "   - Dashboard Minikube: minikube dashboard" "White"
Write-ColoredMessage ""

# Test de connectivite
if ($nodePort) {
    Write-ColoredMessage "Test de connectivite..." "Blue"
    try {
        $response = Invoke-WebRequest -Uri "http://$minikubeIp`:$nodePort" -TimeoutSec 10 -UseBasicParsing
        Write-ColoredMessage "Test de connectivite reussi! Status: $($response.StatusCode)" "Green"
    }
    catch {
        Write-ColoredMessage "Test de connectivite echoue: $($_.Exception.Message)" "Yellow"
        Write-ColoredMessage "Il se peut que l'application ne soit pas encore completement prete." "Yellow"
    }
}
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
