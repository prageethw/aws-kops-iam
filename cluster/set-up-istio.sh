if [[ ! -z "${UPDATE_ISTIO_MESH}" ]]; then
    # generate crds
    echo "# manifest generated with :" $(istioctl version) >resources/istio/base/istio-crds.yaml
    istioctl manifest generate --set profile=minimal --set trafficManagement.enabled=false >>resources/istio/base/istio-crds.yaml
    # generate demo profile that gives everything we need in cluster pretty much
    echo "# manifest generated with :" $(istioctl version) >resources/istio/base/istio-demo-profile.yaml
    istioctl manifest generate --set profile=demo \
                            --set values.kiali.createDemoSecret=false \
                            --set values.kiali.dashboard.grafanaURL="http://grafana:3000" \
                            --set values.kiali.dashboard.jaegerURL="http://jaeger-query:16686" \
                            >>resources/istio/base/istio-demo-profile.yaml
fi
# apply crds to k8s
kubectl apply -f resources/istio/base/istio-crds.yaml
sleep 60
# validate installation success
istioctl verify-install -f resources/istio/base/istio-crds.yaml
# apply  customised demo profile to k8s not use of kustomize here
kustomize build resources/istio/overlays | sed -e "s@ARN@$AWS_SSL_CERT_ARN@g" >istio-install-demo-profile.yaml
kubectl apply -f istio-install-demo-profile.yaml
kubectl -n istio-system rollout status  deployments istio-pilot
kubectl -n istio-system rollout status  deployments istio-ingressgateway
# enable basic auth for add-ons (same file used to enable for nginx basic auth)
kubectl create secret generic sysops --from-file ./keys/auth -n istio-system
# validate installation success
istioctl verify-install -f istio-install-demo-profile.yaml

# enable namespaces to deploy sidecards
kubectl label namespace ops \
    istio-injection=enabled
kubectl label namespace dev \
    istio-injection=enabled
kubectl label namespace test \
    istio-injection=enabled
kubectl label namespace prod \
    istio-injection=enabled


# delete istio
# kubectl delete -f istio-demo-profile.yaml
