FROM registry.access.redhat.com/ubi9/go-toolset:1.23 AS builder
WORKDIR /build
COPY . .
WORKDIR /build/virt-tests
RUN GO_COMPLIANCE_POLICY="exempt_all" go build -o virt-tests ./cmd/virt-tests/...

FROM registry.access.redhat.com/ubi9/ubi-minimal:latest
COPY --from=builder /build/virt-tests/virt-tests /usr/local/bin/virt-tests
COPY --from=builder /build/virt-tests/scripts /opt/tests/scripts
COPY --from=builder /build/virt-tests/tests.json /opt/tests/tests.json
WORKDIR /opt/tests
ENTRYPOINT ["virt-tests"]
