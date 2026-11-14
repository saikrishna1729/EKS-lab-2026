#!/usr/bin/env bash
# Istio ambient mode (sidecar-less): ztunnel (L4 mTLS, per node) + optional waypoint (L7, per namespace).
# Installed by hand on purpose so you see each piece; move it into gitops/platform once you're happy.
source "$(dirname "$0")/../../../scripts/lib.sh"
helm repo add istio https://istio-release.storage.googleapis.com/charts >/dev/null 2>&1 || true
helm repo update istio >/dev/null
V=$ISTIO_VERSION
helm upgrade --install istio-base istio/base -n istio-system --create-namespace --version $V --wait
helm upgrade --install istiod istio/istiod -n istio-system --version $V --set profile=ambient --wait
# VPC CNI is the primary CNI; istio-cni chains onto it to redirect pod traffic to ztunnel
helm upgrade --install istio-cni istio/cni -n istio-system --version $V --set profile=ambient --wait
helm upgrade --install ztunnel istio/ztunnel -n istio-system --version $V --wait
log "Istio $V ambient installed. Enroll the shop:  kubectl label ns shop istio.io/dataplane-mode=ambient"
