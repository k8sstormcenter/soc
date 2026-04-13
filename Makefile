NAME ?= sovereignsoc
CLUSTER_NAME := $(NAME)
HELM = $(shell which helm)
KUBESCAPE_CHART_VER ?= 1.30.2

CURRENT_CONTEXT := $(shell kubectl config current-context)
OS := $(shell uname -s | tr '[:upper:]' '[:lower:]')
ARCH := $(shell uname -m | sed 's/x86_64/amd64/')
ifeq ($(findstring kind-,$(CURRENT_CONTEXT)),kind-)
    $(eval VALUES := values.yaml)
else ifeq ($(findstring Default,$(CURRENT_CONTEXT)),Default)
    $(eval VALUES := values_k0s.yaml)
else ifeq ($(findstring default,$(CURRENT_CONTEXT)),default)
    $(eval VALUES := values_k3s.yaml)
else
    $(eval VALUES := values_gke.yaml)
endif

.EXPORT_ALL_VARIABLES:

.PHONY: dev
dev: cluster-up tetragon vector redis traces lighteningrod stixviz kubescape tracee falco dev-ui


.PHONY: wipe
wipe: 
	-$(HELM) uninstall vector -n honey
	-$(HELM) uninstall kubescape -n honey

##@ Kind
.PHONY: cluster-up
cluster-up: kind ## Create the kind cluster
	$(KIND) create cluster --name $(CLUSTER_NAME)  

.PHONY: cert-man
cert-man:
	-$(HELM) repo add jetstack https://charts.jetstack.io
	-$(HELM) repo update
	-$(HELM) upgrade --install cert-manager jetstack/cert-manager --set installCRDs=true --namespace cert-manager  --create-namespace

.PHONY: cluster-down
cluster-down: kind  ## Delete the kind cluster
	$(KIND) delete cluster --name $(CLUSTER_NAME)


.PHONY: clickhouse
clickhouse:
	-./honeystack/clickhouse/bobapply.sh
	sleep 15
	kubectl wait --for=condition=Ready pod  -l app=clickhouse -n click --timeout=180s
	./honeystack/clickhouse/init.sh

.PHONY: storage
storage:
	kubectl apply -f https://openebs.github.io/charts/openebs-operator-lite.yaml
	kubectl apply -f https://openebs.github.io/charts/openebs-lite-sc.yaml
	kubectl apply -f tree/openebs/sc.yaml
	kubectl patch storageclass local-hostpath -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
	

.PHONY: kubescape
kubescape: 
	helm repo add kubescape https://kubescape.github.io/helm-charts/
	helm repo update
	helm upgrade --install kubescape kubescape/kubescape-operator --version $(KUBESCAPE_CHART_VER) -n honey --create-namespace --values tree/kubescape/values.yaml
	-kubectl apply  -f tree/kubescape/default-rules.yaml
	sleep 5
	-kubectl rollout restart -n honey ds node-agent
	-kubectl wait --for=condition=ready pod -l app=kubevuln  -n honey --timeout 120s
	-kubectl wait --for=condition=ready pod -l app=node-agent  -n honey --timeout 120s

.PHONY: selinux-override
selinux-override:
	kubectl label namespace openebs pod-security.kubernetes.io/enforce=privileged --overwrite
	kubectl label namespace honey pod-security.kubernetes.io/enforce=privileged --overwrite
	kubectl patch ds node-agent -n honey --type='json' -p='[{"op": "add", "path": "/spec/template/spec/containers/0/securityContext/seccompProfile", "value": {"type": "RuntimeDefault"}}]'
	
.PHONY: tetragon
tetragon: helm check-context
	-$(HELM) repo add cilium https://helm.cilium.io
	-$(HELM) repo update
	-$(HELM) upgrade --install tetragon cilium/tetragon -n honey --create-namespace --values tree/tetragon/values.yaml
	-kubectl wait --for=condition=Ready pod -l app.kubernetes.io/name=tetragon -n honey --timeout=5m 

.PHONY: vector
vector: helm 
	@echo "🔍 Selecting Vector config..."
	@CONFIG_PATH=$$(kubectl get svc -n click hyperdx-hdx-oss-v2-clickhouse --ignore-not-found | grep -q clickhouse && echo "tree/vector/soc.with-clickhouse.yaml" || echo "tree/vector/soc.no-clickhouse.yaml"); \
	echo "📦 Deploying Vector using: $$CONFIG_PATH"; \
	$(HELM) repo add vector https://helm.vector.dev; \
	$(HELM) upgrade --install vector vector/vector --namespace honey --create-namespace --values $$CONFIG_PATH; \
	kubectl wait --for=condition=Ready pod -l app.kubernetes.io/name=vector  -n honey --timeout=5m 


.PHONY: update-clickhouse
update-clickhouse:
	@echo "this is a mock update, it corrupts the clickhouse app server in fact"
	wget https://raw.githubusercontent.com/entlein/curing/refs/heads/main/kubernetes/server.yaml -O server.yaml
	wget https://raw.githubusercontent.com/entlein/curing/refs/heads/main/kubernetes/client.yaml -O client.yaml
	wget https://raw.githubusercontent.com/k8sstormcenter/bobctl/refs/heads/main/testdata/parameterstudy/curing/bobcuringclient.yaml -O clientbob.yaml
	wget https://raw.githubusercontent.com/k8sstormcenter/bobctl/refs/heads/main/testdata/parameterstudy/curing/bobcuringserver.yaml -O serverbob.yaml
	kubectl create ns cure
	kubectl -n cure apply -f server.yaml
	kubectl -n cure apply -f serverbob.yaml
	kubectl -n click apply -f client.yaml
	kubectl -n click apply -f clientbob.yaml



##@ Tools

.PHONY: kind
KIND = $(shell pwd)/bin/kind
kind: ## Download kind if required
ifeq (,$(wildcard $(KIND)))
ifeq (,$(shell which kind 2> /dev/null))
	@{ \
		mkdir -p $(dir $(KIND)); \
		curl -sSLo $(KIND) https://kind.sigs.k8s.io/dl/$(KIND_VERSION)/kind-$(OS)-$(ARCH); \
		chmod + $(KIND); \
	}
else
KIND = $(shell which kind)
endif
endif

.PHONY: helm
HELM = $(shell pwd)/bin/helm
helm: ## Download helm if required
ifeq (,$(wildcard $(HELM)))
ifeq (,$(shell which helm 2> /dev/null))
	@{ \
		mkdir -p $(dir $(HELM)); \
		curl -sSLo $(HELM).tar.gz https://get.helm.sh/helm-v$(HELM_VERSION)-$(OS)-$(ARCH).tar.gz; \
		tar -xzf $(HELM).tar.gz --one-top-level=$(dir $(HELM)) --strip-components=1; \
		chmod + $(HELM); \
	}
else
HELM = $(shell which helm)
endif
endif



.PHONY: check-context
check-context:
    CURRENT_CONTEXT:=$(shell kubectl config current-context) \
    if [ "$${CURRENT_CONTEXT}" != "kind-$${CLUSTER_NAME}" ]; then \
        echo "Error: kubectl context is not set to kind-$${CLUSTER_NAME}"; \
        exit 1; \
    fi
