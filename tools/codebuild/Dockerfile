FROM aws/codebuild/standard:7.0

ARG HELM_VERSION=3.17.3

RUN set -eu; \
    cd /tmp; \
    archive="helm-v${HELM_VERSION}-linux-amd64.tar.gz"; \
    curl --fail --silent --show-error --location \
      "https://get.helm.sh/${archive}" \
      --output "${archive}"; \
    curl --fail --silent --show-error --location \
      "https://get.helm.sh/${archive}.sha256sum" \
      --output "${archive}.sha256sum"; \
    sha256sum --check "${archive}.sha256sum"; \
    tar --extract --gzip --file "${archive}"; \
    install --mode 0755 linux-amd64/helm /usr/local/bin/helm; \
    rm -rf "/tmp/${archive}" "/tmp/${archive}.sha256sum" /tmp/linux-amd64; \
    helm version --short
