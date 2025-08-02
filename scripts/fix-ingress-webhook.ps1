# Script pour resoudre les problemes de webhook avec l'Ingress Controller

Write-Host "🔧 Resolution des problemes de webhook Ingress Controller..." -ForegroundColor Yellow

# Arreter tous les processus qui pourraient interferer
Write-Host "Suppression complete de l'Ingress Controller..." -ForegroundColor Blue

# Supprimer le deploiement existant
helm uninstall ingress-nginx -n ingress-nginx 2>$null

# Supprimer les resources restantes
kubectl delete validatingwebhookconfiguration ingress-nginx-admission 2>$null
kubectl delete mutatingwebhookconfiguration ingress-nginx-admission 2>$null
kubectl delete clusterrole ingress-nginx 2>$null
kubectl delete clusterrolebinding ingress-nginx 2>$null
kubectl delete ingressclass nginx 2>$null

# Supprimer le namespace et attendre
kubectl delete namespace ingress-nginx 2>$null
Write-Host "Attente de la suppression complete..." -ForegroundColor Yellow
Start-Sleep -Seconds 20

# Verifier que tout est supprime
$remainingPods = kubectl get pods -n ingress-nginx 2>$null
if ($remainingPods) {
    Write-Host "Suppression forcee des ressources restantes..." -ForegroundColor Yellow
    kubectl delete pods --all -n ingress-nginx --force --grace-period=0 2>$null
    Start-Sleep -Seconds 10
}

# Reinstaller proprement
Write-Host "Reinstallation propre de l'Ingress Controller..." -ForegroundColor Green

helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

# Installation avec configuration minimale pour eviter les problemes de webhook
helm install ingress-nginx ingress-nginx/ingress-nginx `
    --namespace ingress-nginx `
    --create-namespace `
    --set controller.service.type=NodePort `
    --set controller.service.nodePorts.http=30080 `
    --set controller.service.nodePorts.https=30443 `
    --set controller.admissionWebhooks.enabled=false `
    --set controller.admissionWebhooks.patch.enabled=false `
    --set controller.admissionWebhooks.createSecretJob.enabled=false `
    --set controller.admissionWebhooks.patchWebhookJob.enabled=false `
    --set controller.config.use-forwarded-headers=true `
    --set controller.ingressClassResource.default=true `
    --set controller.ingressClassResource.controllerValue="k8s.io/ingress-nginx" `
    --wait `
    --timeout=600s

if ($LASTEXITCODE -eq 0) {
    Write-Host "✅ Ingress Controller reinstalle avec succes!" -ForegroundColor Green

    # Attendre que le pod soit pret
    Write-Host "Attente que l'Ingress Controller soit pret..." -ForegroundColor Yellow
    kubectl wait --namespace ingress-nginx `
        --for=condition=ready pod `
        --selector=app.kubernetes.io/component=controller `
        --timeout=300s

    if ($LASTEXITCODE -eq 0) {
        Write-Host "✅ Ingress Controller pret!" -ForegroundColor Green
        Write-Host ""
        Write-Host "Vous pouvez maintenant relancer le deploiement:" -ForegroundColor Cyan
        Write-Host ".\deploy-minikube.ps1" -ForegroundColor White
    }
    else {
        Write-Host "⚠️ L'Ingress Controller prend plus de temps que prevu a etre pret." -ForegroundColor Yellow
        Write-Host "Verifiez avec: kubectl get pods -n ingress-nginx" -ForegroundColor White
    }
}
else {
    Write-Host "❌ Echec de la reinstallation de l'Ingress Controller" -ForegroundColor Red
    Write-Host "Vous pouvez essayer de deployer sans Ingress:" -ForegroundColor Yellow
    Write-Host ".\deploy-minikube.ps1 (et repondre 'n' a l'ingress)" -ForegroundColor White
}

Write-Host ""
Write-Host "Statut actuel:" -ForegroundColor Blue
kubectl get pods -n ingress-nginx 2>$null
kubectl get svc -n ingress-nginx 2>$null
