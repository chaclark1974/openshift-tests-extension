FROM registry.access.redhat.com/ubi9/go-toolset:1.23 AS builder
WORKDIR /build
COPY . .
RUN make build

FROM registry.access.redhat.com/ubi9/ubi-minimal:latest
COPY --from=builder /build/quay-tests /usr/local/bin/quay-tests
COPY --from=builder /build/scripts /opt/tests/scripts
COPY --from=builder /build/tests.json /opt/tests/tests.json
WORKDIR /opt/tests
ENTRYPOINT ["quay-tests"]
