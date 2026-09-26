ARG BASE_IMAGE
FROM ${BASE_IMAGE}

ARG IMAGE_VERSION=4.2.0-r1

USER root

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
