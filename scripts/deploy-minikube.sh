#!/bin/bash

# Script pour déployer les microservices NestJS sur Minikube avec Helm

set -e

echo "🚀 Déploiement des microservices NestJS sur Minikube avec Helm"

# Vérifier que Minikube est démarré
if ! minikube status | grep -q "Running"; then
    echo "❌ Minikube n'est pas démarré. Démarrage de Minikube..."
    minikube start --driver=docker --memory=4096 --cpus=2
fi

# Configurer l'environnement Docker pour utiliser celui de Minikube
echo "🔧 Configuration de l'environnement Docker pour Minikube..."
eval $(minikube docker-env)

# Construire les images Docker dans l'environnement Minikube
echo "🏗️ Construction des images Docker..."

# Construire l'image pour le service products
echo "📦 Construction de l'image products..."
docker build -f Dockerfile --build-arg APP_NAME=products -t nestjs-microservice/products:latest .

# Construire l'image pour l'API Gateway
echo "📦 Construction de l'image api-gateway..."
docker build -f Dockerfile --build-arg APP_NAME=api-gateway -t nestjs-microservice/api-gateway:latest .

# Vérifier que Helm est installé
if ! command -v helm &> /dev/null; then
    echo "❌ Helm n'est pas installé. Veuillez installer Helm d'abord."
    echo "Visitez: https://helm.sh/docs/intro/install/"
    exit 1
fi

# Ajouter le repository Nginx Ingress si l'ingress est activé
echo "🔧 Configuration de l'Ingress Controller..."
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

# Installer l'Ingress Controller si nécessaire
if ! kubectl get pods -n ingress-nginx | grep -q ingress-nginx-controller; then
    echo "📥 Installation de l'Ingress Controller..."
    helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
        --namespace ingress-nginx \
        --create-namespace \
        --wait

    # Attendre que l'Ingress Controller soit prêt
    kubectl wait --namespace ingress-nginx \
        --for=condition=ready pod \
        --selector=app.kubernetes.io/component=controller \
        --timeout=300s
fi

# Déployer avec Helm
echo "🚀 Déploiement avec Helm..."
helm upgrade --install nestjs-microservices ./helm/nestjs-microservices \
    --values ./helm/nestjs-microservices/values-minikube.yaml \
    --wait \
    --timeout=300s

# Attendre que tous les pods soient prêts
echo "⏳ Attente que tous les pods soient prêts..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/instance=nestjs-microservices --timeout=300s

# Afficher le statut du déploiement
echo "📊 Statut du déploiement:"
kubectl get pods -l app.kubernetes.io/instance=nestjs-microservices
kubectl get services -l app.kubernetes.io/instance=nestjs-microservices

# Obtenir l'URL d'accès
MINIKUBE_IP=$(minikube ip)
NODE_PORT=$(kubectl get service nestjs-microservices-api-gateway -o jsonpath='{.spec.ports[0].nodePort}')

echo ""
echo "✅ Déploiement terminé avec succès!"
echo ""
echo "🌐 URLs d'accès:"
echo "   - API Gateway (NodePort): http://$MINIKUBE_IP:$NODE_PORT"
echo "   - API Gateway (Ingress): http://nestjs-microservices.local (ajoutez l'entrée dans /etc/hosts)"
echo ""
echo "📝 Pour ajouter l'entrée hosts:"
echo "   echo \"$MINIKUBE_IP nestjs-microservices.local\" | sudo tee -a /etc/hosts"
echo ""
echo "🔍 Commandes utiles:"
echo "   - Voir les logs: kubectl logs -f deployment/nestjs-microservices-api-gateway"
echo "   - Voir les pods: kubectl get pods"
echo "   - Tunnel Minikube: minikube tunnel"
echo ""
