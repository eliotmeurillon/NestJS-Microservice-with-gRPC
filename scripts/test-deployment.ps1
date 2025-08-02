# Script de test pour valider le déploiement Helm

Write-Host "🧪 Test du déploiement NestJS sur Minikube" -ForegroundColor Green

# Fonction pour tester l'accessibilité d'une URL
function Test-Url {
    param($url, $description)

    try {
        $response = Invoke-WebRequest -Uri $url -TimeoutSec 10 -UseBasicParsing
        if ($response.StatusCode -eq 200) {
            Write-Host "✅ $description - OK (Status: $($response.StatusCode))" -ForegroundColor Green
            return $true
        } else {
            Write-Host "❌ $description - FAILED (Status: $($response.StatusCode))" -ForegroundColor Red
            return $false
        }
    } catch {
        Write-Host "❌ $description - FAILED (Error: $($_.Exception.Message))" -ForegroundColor Red
        return $false
    }
}

# Vérifier que Minikube est démarré
Write-Host "🔍 Vérification du statut de Minikube..." -ForegroundColor Blue
$minikubeStatus = minikube status 2>$null
if ($minikubeStatus -notmatch "Running") {
    Write-Host "❌ Minikube n'est pas démarré" -ForegroundColor Red
    exit 1
}
Write-Host "✅ Minikube est démarré" -ForegroundColor Green

# Vérifier que le déploiement Helm existe
Write-Host "🔍 Vérification du déploiement Helm..." -ForegroundColor Blue
$helmStatus = helm status nestjs-microservices 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Le déploiement Helm 'nestjs-microservices' n'existe pas" -ForegroundColor Red
    exit 1
}
Write-Host "✅ Déploiement Helm trouvé" -ForegroundColor Green

# Vérifier que tous les pods sont en cours d'exécution
Write-Host "🔍 Vérification du statut des pods..." -ForegroundColor Blue
$pods = kubectl get pods -l app.kubernetes.io/instance=nestjs-microservices -o jsonpath='{.items[*].status.phase}'
$podsArray = $pods -split ' '
$runningPods = $podsArray | Where-Object { $_ -eq "Running" }

if ($podsArray.Count -eq 0) {
    Write-Host "❌ Aucun pod trouvé" -ForegroundColor Red
    exit 1
} elseif ($runningPods.Count -eq $podsArray.Count) {
    Write-Host "✅ Tous les pods sont en cours d'exécution ($($runningPods.Count)/$($podsArray.Count))" -ForegroundColor Green
} else {
    Write-Host "❌ Certains pods ne fonctionnent pas ($($runningPods.Count)/$($podsArray.Count))" -ForegroundColor Red
    kubectl get pods -l app.kubernetes.io/instance=nestjs-microservices
    exit 1
}

# Obtenir les informations de connexion
$minikubeIp = minikube ip
$nodePort = kubectl get service nestjs-microservices-api-gateway -o jsonpath='{.spec.ports[0].nodePort}'

Write-Host "🌐 Informations de connexion:" -ForegroundColor Cyan
Write-Host "   - IP Minikube: $minikubeIp" -ForegroundColor White
Write-Host "   - Port NodePort: $nodePort" -ForegroundColor White

# Test de connectivité via NodePort
Write-Host "🔍 Test de connectivité via NodePort..." -ForegroundColor Blue
$nodePortUrl = "http://$minikubeIp`:$nodePort"
$nodePortSuccess = Test-Url $nodePortUrl "API Gateway (NodePort)"

# Test de connectivité via Ingress (si configuré)
Write-Host "🔍 Test de connectivité via Ingress..." -ForegroundColor Blue
$ingressUrl = "http://nestjs-microservices.local"
$ingressSuccess = Test-Url $ingressUrl "API Gateway (Ingress)"

# Vérifier les services
Write-Host "🔍 Vérification des services..." -ForegroundColor Blue
$services = kubectl get services -l app.kubernetes.io/instance=nestjs-microservices -o jsonpath='{.items[*].metadata.name}'
$servicesArray = $services -split ' '
Write-Host "✅ Services trouvés: $($servicesArray -join ', ')" -ForegroundColor Green

# Afficher le résumé
Write-Host ""
Write-Host "📊 Résumé des tests:" -ForegroundColor Yellow
Write-Host "   - Minikube: ✅" -ForegroundColor Green
Write-Host "   - Déploiement Helm: ✅" -ForegroundColor Green
Write-Host "   - Pods: $(if ($runningPods.Count -eq $podsArray.Count) { '✅' } else { '❌' })" -ForegroundColor $(if ($runningPods.Count -eq $podsArray.Count) { 'Green' } else { 'Red' })
Write-Host "   - NodePort: $(if ($nodePortSuccess) { '✅' } else { '❌' })" -ForegroundColor $(if ($nodePortSuccess) { 'Green' } else { 'Red' })
Write-Host "   - Ingress: $(if ($ingressSuccess) { '✅' } else { '❌' })" -ForegroundColor $(if ($ingressSuccess) { 'Green' } else { 'Red' })

if ($nodePortSuccess -or $ingressSuccess) {
    Write-Host ""
    Write-Host "🎉 Le déploiement semble fonctionner correctement!" -ForegroundColor Green
    Write-Host ""
    Write-Host "🌐 URLs d'accès:" -ForegroundColor Cyan
    if ($nodePortSuccess) {
        Write-Host "   - NodePort: $nodePortUrl" -ForegroundColor White
    }
    if ($ingressSuccess) {
        Write-Host "   - Ingress: $ingressUrl" -ForegroundColor White
    }
} else {
    Write-Host ""
    Write-Host "❌ Le déploiement a des problèmes de connectivité" -ForegroundColor Red
    Write-Host ""
    Write-Host "🔍 Debug:" -ForegroundColor Yellow
    Write-Host "   - Vérifiez les logs: kubectl logs -f deployment/nestjs-microservices-api-gateway" -ForegroundColor White
    Write-Host "   - Vérifiez les pods: kubectl get pods" -ForegroundColor White
    Write-Host "   - Vérifiez les services: kubectl get services" -ForegroundColor White
}

Write-Host ""
