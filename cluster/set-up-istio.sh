if [[ ! -z "${UPDATE_ISTIO_MESH}" ]]; then
    # generate crds
    istioctl manifest generate --set profile=minimal --set trafficManagement.enabled=false >resources/istio/base/istio-crds.yaml
    echo "# manifest generated with :" $(istioctl version) >> resources/istio/base/istio-crds.yaml
    # generate demo profile that gives everything we need in cluster pretty much
    echo "# manifest generated with :" $(istioctl version) > resources/istio/base/istio-demo-profile.yaml
    istioctl manifest generate --set profile=demo \
                            --set values.kiali.createDemoSecret=false \
                            --set values.kiali.dashboard.grafanaURL="http://grafana:3000" \
                            --set values.kiali.dashboard.jaegerURL="http://jaeger-query:16686" \
                            >>resources/istio/base/istio-demo-profile.yaml
    # apply new crds to k8s
    kubectl apply -f resources/istio/base/istio-crds.yaml
fi

ISTIO_INIT_SLEEP=60
echo "Waiting $ISTIO_INIT_SLEEP sec for ISTIO CRDS to become available..."
echo "count down is ..."
while [ $ISTIO_INIT_SLEEP -gt 0 ]; do
    echo -ne "$ISTIO_INIT_SLEEP\033[0K\r" 
    sleep 1
    : $((ISTIO_INIT_SLEEP--))
done

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

# enable kiali by seting scret

KIALI_USERNAME=$(echo -n sysops | base64)
KIALI_PASSPHRASE=$(echo -n $BASIC_AUTH_PWD | base64)
# create secret
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: kiali
  namespace: istio-system
  labels:
    app: kiali
type: Opaque
data:
  username: $KIALI_USERNAME
  passphrase: $KIALI_PASSPHRASE
EOF

# create ingress for add-ons
cat resources/istio-add-ons-using-nginx-ingress.yaml | sed -e     "s@MESH_GRAFANA_ADDR@$MESH_GRAFANA_ADDR@g; \
                                                                   s@MESH_PROM_ADDR@$MESH_PROM_ADDR@g; \
                                                                   s@MESH_KIALI_ADDR@$MESH_KIALI_ADDR@g; \
                                                                   s@MESH_JAEGER_ADDR@$MESH_JAEGER_ADDR@g" | \
                                                                   tee istio-add-ons-using-nginx-ingress.temp.yaml
kubectl apply -f istio-add-ons-using-nginx-ingress.temp.yaml
# delete istio
# kubectl delete -f istio-demo-profile.yaml
