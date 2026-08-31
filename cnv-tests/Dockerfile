FROM registry.access.redhat.com/ubi9/go-toolset:1.23 AS builder
WORKDIR /build
COPY . .
WORKDIR /build/cnv-tests
RUN GO_COMPLIANCE_POLICY="exempt_all" go build -o cnv-tests ./cmd/cnv-tests/...

FROM registry.access.redhat.com/ubi9/ubi-minimal:latest
COPY --from=builder /build/cnv-tests/cnv-tests /usr/local/bin/cnv-tests
COPY --from=builder /build/cnv-tests/scripts /opt/tests/scripts
COPY --from=builder /build/cnv-tests/tests.json /opt/tests/tests.json
WORKDIR /opt/tests
ENTRYPOINT ["cnv-tests"]
