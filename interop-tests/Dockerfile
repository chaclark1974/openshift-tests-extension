FROM registry.access.redhat.com/ubi9/go-toolset:1.23 AS builder
USER 0
WORKDIR /build
COPY . .
WORKDIR /build/interop-tests
RUN GO_COMPLIANCE_POLICY="exempt_all" go build -buildvcs=false -o interop-tests ./cmd/interop-tests/...

FROM registry.access.redhat.com/ubi9/ubi-minimal:latest
COPY --from=builder /build/interop-tests/interop-tests /usr/local/bin/interop-tests
COPY --from=builder /build/interop-tests/scripts /opt/tests/scripts
COPY --from=builder /build/interop-tests/tests.json /opt/tests/tests.json
WORKDIR /opt/tests
ENTRYPOINT ["interop-tests"]
