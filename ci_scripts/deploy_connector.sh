#!/usr/bin/env bash
set -e

#Make sure to check and clean previously failed deployment
echo "Checking if previous deployment exist..."
if [ "`helm ls --short`" == "" ]; then
   echo "Nothing to clean, ready for deployment"
else
   helm delete $(helm ls --short)
fi

# Clone splunk-connect-for-kubernetes repo
cd /opt
# OUR fork. The upstream is archived and its values.yaml still names the splunk/* images,
# which no longer exist on Docker Hub — a functional test against it would fail on
# ImagePullBackOff before it ever exercised the plugin.
git clone https://github.com/ephico2real2/splunk-connect-for-kubernetes.git
cd splunk-connect-for-kubernetes

minikube image load ephico2real/fluentd-hec:recent

echo "Deploying k8s-connect with latest changes"
# The objects/metrics/aggr images are scaffolding here — the image under test is only
# fluentd-hec — but the chart repo's ci_scripts/sck_values.yml still names the deleted
# splunk/* images, and `-f` would resurrect them over the chart's fixed defaults. `--set`
# outranks `-f`, so pin all three to our published hardened builds explicitly.
helm install ci-sck --set global.splunk.hec.token=$CI_SPLUNK_HEC_TOKEN \
--set global.splunk.hec.host=$CI_SPLUNK_HOST \
--set kubelet.serviceMonitor.https=true \
--set splunk-kubernetes-logging.image.name=ephico2real/fluentd-hec \
--set splunk-kubernetes-logging.image.tag=recent \
--set splunk-kubernetes-logging.image.pullPolicy=IfNotPresent \
--set splunk-kubernetes-objects.image.name=ephico2real/kube-objects \
--set splunk-kubernetes-objects.image.tag=1.2.3-h1 \
--set splunk-kubernetes-metrics.image.name=ephico2real/k8s-metrics \
--set splunk-kubernetes-metrics.image.tag=1.2.3-h1 \
--set splunk-kubernetes-metrics.imageAgg.name=ephico2real/k8s-metrics-aggr \
--set splunk-kubernetes-metrics.imageAgg.tag=1.2.3-h1 \
-f ci_scripts/sck_values.yml helm-chart/splunk-connect-for-kubernetes
# kubectl get pod | grep "ci-sck-splunk-kubernetes-logging" | awk 'NR==1{print $1}
kubectl get pod
# wait for deployment to finish
# metric and logging deamon set for each node + aggr + object + splunk
PODS=$((MINIKUBE_NODE_COUNTS*2+2+1))
until kubectl get pod | grep Running | [[ $(wc -l) == $PODS ]]; do
   kubectl get pod
   sleep 2;
done
