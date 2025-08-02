# Script de validation du chart Helm

Write-Host "🔍 Validation du chart Helm NestJS Microservices" -ForegroundColor Green

$chartPath = "./helm/nestjs-microservices"
$errors = 0

# Vérifier que le dossier du chart existe
if (!(Test-Path $chartPath)) {
    Write-Host "❌ Le dossier du chart $chartPath n'existe pas" -ForegroundColor Red
    exit 1
}

Write-Host "✅ Dossier du chart trouvé: $chartPath" -ForegroundColor Green

# Vérifier que Helm est installé
if (!(Get-Command helm -ErrorAction SilentlyContinue)) {
    Write-Host "❌ Helm n'est pas installé" -ForegroundColor Red
    exit 1
}

Write-Host "✅ Helm est installé" -ForegroundColor Green

# Helm lint
Write-Host "🔍 Exécution de helm lint..." -ForegroundColor Blue
$lintResult = helm lint $chartPath 2>&1
if ($LASTEXITCODE -eq 0) {
    Write-Host "✅ Helm lint: OK" -ForegroundColor Green
} else {
    Write-Host "❌ Helm lint: ERREUR" -ForegroundColor Red
    Write-Host $lintResult -ForegroundColor Yellow
    $errors++
}

# Template generation test avec values par défaut
Write-Host "🔍 Test de génération des templates (values par défaut)..." -ForegroundColor Blue
$templateResult = helm template test-release $chartPath 2>&1
if ($LASTEXITCODE -eq 0) {
    Write-Host "✅ Génération des templates: OK" -ForegroundColor Green
} else {
    Write-Host "❌ Génération des templates: ERREUR" -ForegroundColor Red
    Write-Host $templateResult -ForegroundColor Yellow
    $errors++
}

# Template generation test avec values-minikube
Write-Host "🔍 Test de génération des templates (values-minikube)..." -ForegroundColor Blue
$templateMinikubeResult = helm template test-release $chartPath --values "$chartPath/values-minikube.yaml" 2>&1
if ($LASTEXITCODE -eq 0) {
    Write-Host "✅ Génération des templates (minikube): OK" -ForegroundColor Green
} else {
    Write-Host "❌ Génération des templates (minikube): ERREUR" -ForegroundColor Red
    Write-Host $templateMinikubeResult -ForegroundColor Yellow
    $errors++
}

# Template generation test avec values-production
Write-Host "🔍 Test de génération des templates (values-production)..." -ForegroundColor Blue
$templateProdResult = helm template test-release $chartPath --values "$chartPath/values-production.yaml" 2>&1
if ($LASTEXITCODE -eq 0) {
    Write-Host "✅ Génération des templates (production): OK" -ForegroundColor Green
} else {
    Write-Host "❌ Génération des templates (production): ERREUR" -ForegroundColor Red
    Write-Host $templateProdResult -ForegroundColor Yellow
    $errors++
}

# Dry-run installation test (si kubectl est disponible)
if (Get-Command kubectl -ErrorAction SilentlyContinue) {
    Write-Host "🔍 Test d'installation dry-run..." -ForegroundColor Blue
    $dryRunResult = helm install test-release $chartPath --values "$chartPath/values-minikube.yaml" --dry-run --debug 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✅ Installation dry-run: OK" -ForegroundColor Green
    } else {
        Write-Host "❌ Installation dry-run: ERREUR" -ForegroundColor Red
        Write-Host $dryRunResult -ForegroundColor Yellow
        $errors++
    }
} else {
    Write-Host "⚠️ kubectl non disponible, skip du test dry-run" -ForegroundColor Yellow
}

# Vérifier les fichiers requis
$requiredFiles = @(
    "Chart.yaml",
    "values.yaml",
    "values-minikube.yaml",
    "values-production.yaml",
    "templates/_helpers.tpl",
    "templates/configmap.yaml",
    "templates/api-gateway-deployment.yaml",
    "templates/api-gateway-service.yaml",
    "templates/products-deployment.yaml",
    "templates/products-service.yaml",
    "templates/ingress.yaml",
    "templates/hpa.yaml"
)

Write-Host "🔍 Vérification des fichiers requis..." -ForegroundColor Blue
foreach ($file in $requiredFiles) {
    $filePath = Join-Path $chartPath $file
    if (Test-Path $filePath) {
        Write-Host "✅ $file" -ForegroundColor Green
    } else {
        Write-Host "❌ $file manquant" -ForegroundColor Red
        $errors++
    }
}

# Résumé
Write-Host ""
Write-Host "📊 Résumé de la validation:" -ForegroundColor Yellow
if ($errors -eq 0) {
    Write-Host "🎉 Validation réussie! Le chart Helm est prêt pour le déploiement." -ForegroundColor Green
    Write-Host ""
    Write-Host "🚀 Commandes de déploiement:" -ForegroundColor Cyan
    Write-Host "   - Minikube: .\scripts\deploy-minikube.ps1" -ForegroundColor White
    Write-Host "   - Manuel: helm install nestjs-microservices $chartPath --values $chartPath/values-minikube.yaml" -ForegroundColor White
    exit 0
} else {
    Write-Host "❌ Validation échouée avec $errors erreur(s). Veuillez corriger les problèmes avant le déploiement." -ForegroundColor Red
    exit 1
}
