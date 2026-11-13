# Курсовой образ SONiC: docker-sonic-vs + заглушки sudo/docker для штатного CLI
ARG BASE=docker-sonic-vs:202511
FROM ${BASE}
COPY sudo-shim /usr/local/bin/sudo
COPY docker-shim /usr/local/bin/docker
RUN chmod +x /usr/local/bin/sudo /usr/local/bin/docker \
 && ln -sf /usr/bin/vtysh /usr/local/bin/rvtysh
