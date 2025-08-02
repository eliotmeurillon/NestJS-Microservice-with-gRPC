# Script PowerShell pour nettoyer le déploiement Minikube

Write-Host "🧹 Nettoyage du déploiement NestJS sur Minikube" -ForegroundColor Yellow

# Supprimer le déploiement Helm
Write-Host "🗑️ Suppression du déploiement Helm..." -ForegroundColor Blue
helm uninstall nestjs-microservices

# Supprimer l'Ingress Controller (optionnel)
$removeIngress = Read-Host "Voulez-vous aussi supprimer l'Ingress Controller? (y/N)"
if ($removeIngress -eq "y" -or $removeIngress -eq "Y") {
    Write-Host "🗑️ Suppression de l'Ingress Controller..." -ForegroundColor Blue
    helm uninstall ingress-nginx -n ingress-nginx
    kubectl delete namespace ingress-nginx
}

# Configurer l'environnement Docker pour utiliser celui de Minikube
Write-Host "🔧 Configuration de l'environnement Docker pour Minikube..." -ForegroundColor Blue
& minikube -p minikube docker-env --shell powershell | Invoke-Expression

# Supprimer les images Docker locales
Write-Host "🗑️ Suppression des images Docker..." -ForegroundColor Blue
docker rmi nestjs-microservice/products:latest -f 2>$null
docker rmi nestjs-microservice/api-gateway:latest -f 2>$null

# Nettoyer les images Docker inutilisées
Write-Host "🧹 Nettoyage des images Docker inutilisées..." -ForegroundColor Blue
docker image prune -f

Write-Host ""
Write-Host "✅ Nettoyage terminé!" -ForegroundColor Green
Write-Host ""
Write-Host "🔍 Commandes utiles:" -ForegroundColor Cyan
Write-Host "   - Voir les pods restants: kubectl get pods" -ForegroundColor White
Write-Host "   - Arrêter Minikube: minikube stop" -ForegroundColor White
Write-Host "   - Supprimer Minikube: minikube delete" -ForegroundColor White
Write-Host ""
