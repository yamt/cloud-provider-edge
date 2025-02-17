# Copyright 2019 Midokura
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

KUBERNETES_VERSION=1.16.0
SOURCES := $(shell find . -name 'm*.go')
GOOS ?= $(shell go env GOOS)
GOARCH ?= $(shell go env GOARCH)
VERSION ?= $(shell git describe --exact-match 2> /dev/null || \
                 git describe --match=$(git rev-parse --short=8 HEAD) --always --dirty --abbrev=8)
LDFLAGS   := "-w -s -X 'main.version=${VERSION}'"

export GO111MODULE=on

edge-cloud-controller-manager-amd64-linux: $(SOURCES)
	CGO_ENABLED=0 GOARCH=amd64 GOOS=linux go build \
		-ldflags $(LDFLAGS) \
		-o edge-cloud-controller-manager-amd64-linux \
		cmd/edge-cloud-controller-manager/main.go

edge-cloud-controller-manager-arm64-linux: $(SOURCES)
	CGO_ENABLED=0 GOARCH=arm64 GOOS=linux go build \
		-ldflags $(LDFLAGS) \
		-o edge-cloud-controller-manager-arm64-linux \
		cmd/edge-cloud-controller-manager/main.go

.PHONY: check
check: verify-fmt verify-lint vet

.PHONY: test
test:
	go test -count=1 -race -v $(shell go list ./...)

.PHONY: verify-fmt
verify-fmt:
	./hack/verify-gofmt.sh

.PHONY: verify-lint
verify-lint:
	which golint 2>&1 >/dev/null || go get golang.org/x/lint/golint
	golint -set_exit_status $(shell go list ./...)

.PHONY: vet
vet:
	go vet ./...

.PHONY: update-fmt
update-fmt:
	./hack/update-gofmt.sh

clean:
	rm -f edge-cloud-controller-manager*

clean-dependencies:
	git checkout -- go.mod go.sum

push-amd64-linux: edge-cloud-controller-manager-amd64-linux
	cp edge-cloud-controller-manager-amd64-linux edge-cloud-controller-manager
	docker build -t midokura/edge-cloud-controller-manager:amd64-linux-latest .
	docker push midokura/edge-cloud-controller-manager:amd64-linux-latest

push-arm64-linux: edge-cloud-controller-manager-arm64-linux
	cp edge-cloud-controller-manager-arm64-linux edge-cloud-controller-manager
	docker build -t midokura/edge-cloud-controller-manager:arm64-linux-latest .
	docker push midokura/edge-cloud-controller-manager:arm64-linux-latest

push: push-amd64-linux push-arm64-linux
	rm -rf ~/.docker/manifests/docker.io_midokura_edge-cloud-controller-manager-latest/
	docker manifest create --amend \
		midokura/edge-cloud-controller-manager:latest \
		midokura/edge-cloud-controller-manager:amd64-linux-latest \
		midokura/edge-cloud-controller-manager:arm64-linux-latest
	docker manifest annotate midokura/edge-cloud-controller-manager midokura/edge-cloud-controller-manager:amd64-linux-latest --arch amd64 --os linux 
	docker manifest annotate midokura/edge-cloud-controller-manager midokura/edge-cloud-controller-manager:arm64-linux-latest --arch arm64 --os linux # --variant v8
	docker manifest push midokura/edge-cloud-controller-manager:latest

dependencies: clean-dependencies 
	go mod init github.com/midokura/kubernetes/cloud-provider-edge
	./switch_kubernetes_version.sh $(KUBERNETES_VERSION)

run: edge-cloud-controller-manager-$(GOARCH)-$(GOOS)
	sudo --preserve-env ./edge-cloud-controller-manager-$(GOARCH)-$(GOOS) --cloud-provider=edge --cloud-config=examples/edge.conf --leader-elect=false --use-service-account-credentials --client-ca-file=/var/lib/rancher/k3s/server/tls/client-ca.crt --kubeconfig=/etc/rancher/k3s/k3s.yaml --requestheader-client-ca-file=/var/lib/rancher/k3s/server/tls/request-header-ca.crt --allow-untagged-cloud --v=1 --vmodule=edge_config=5 --feature-gates='LegacyNodeRoleBehavior=false'

# Note: --feature-gates='LegacyNodeRoleBehavior=false' is needed due to master not included in nodes able to provide load balancing.
#       See https://github.com/kubernetes/kubernetes/blob/37c3a4da97a866a863eb71543a79a56e9834da14/pkg/controller/service/service_controller.go#L642
