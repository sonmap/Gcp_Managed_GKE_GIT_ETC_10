ARG BASE_IMAGE
FROM ${BASE_IMAGE}

ARG IMAGE_VERSION=4.2.0-r2

USER root

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
       ca-certificates \
       curl \
       git \
       gnupg \
    && echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" \
       > /etc/apt/sources.list.d/google-cloud-sdk.list \
    && curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg \
       | gpg --dearmor -o /usr/share/keyrings/cloud.google.gpg \
    && apt-get update \
    && apt-get install -y --no-install-recommends google-cloud-cli \
    && rm -rf /var/lib/apt/lists/*

RUN python -m pip install --no-cache-dir \
      pandas \
      pyarrow \
      db-dtypes \
      google-cloud-bigquery \
      google-cloud-bigquery-storage \
      google-cloud-storage

RUN printf '%s\n' "sandbox-jupyter-standard ${IMAGE_VERSION}" \
    > /etc/sandbox-image-version

USER jovyan
WORKDIR /home/jovyan
