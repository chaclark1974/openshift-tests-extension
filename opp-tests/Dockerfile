FROM registry.access.redhat.com/ubi9/go-toolset:1.23 AS builder
WORKDIR /build
COPY . .
WORKDIR /build/opp-tests
RUN GO_COMPLIANCE_POLICY="exempt_all" go build -o opp-tests ./cmd/opp-tests/...

FROM registry.access.redhat.com/ubi9/ubi-minimal:latest
COPY --from=builder /build/opp-tests/opp-tests /usr/local/bin/opp-tests
COPY --from=builder /build/opp-tests/scripts /opt/tests/scripts
COPY --from=builder /build/opp-tests/tests.json /opt/tests/tests.json
WORKDIR /opt/tests
ENTRYPOINT ["opp-tests"]
