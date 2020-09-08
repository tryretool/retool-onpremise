#!/usr/bin/env bash
echo "install helm"

# installs helm with bash commands for easier command line integration
curl https://raw.githubusercontent.com/kubernetes/helm/master/scripts/get | bash

# add a service account within a namespace to segregate tiller
kubectl --namespace kube-system create sa tiller

# create a cluster role binding for tiller
kubectl create clusterrolebinding tiller \
    --clusterrole cluster-admin \
    --serviceaccount=kube-system:tiller

echo "initialize helm"

# initialized helm within the tiller service account
helm init --service-account tiller

# updates the repos for Helm repo integration
helm repo update

echo "verify helm"

# verify that helm is installed in the cluster
kubectl get deploy,svc tiller-deploy -n kube-system