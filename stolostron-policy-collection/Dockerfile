FROM registry.access.redhat.com/ubi9/go-toolset:1.23 AS builder
WORKDIR /build
COPY . .
WORKDIR /build/stolostron-policy-collection
RUN GO_COMPLIANCE_POLICY="exempt_all" go build -o stolostron-policy-collection ./cmd/stolostron-policy-collection/...

FROM registry.access.redhat.com/ubi9/ubi-minimal:latest
COPY --from=builder /build/stolostron-policy-collection/stolostron-policy-collection /usr/local/bin/stolostron-policy-collection
COPY --from=builder /build/stolostron-policy-collection/scripts /opt/tests/scripts
COPY --from=builder /build/stolostron-policy-collection/tests.json /opt/tests/tests.json
WORKDIR /opt/tests
ENTRYPOINT ["stolostron-policy-collection"]
