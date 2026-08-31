#!/bin/bash
set -euxo pipefail
shopt -s inherit_errexit 2>/dev/null || true

if [[ -z "${KUBECONFIG:-}" ]]; then
    echo "SKIP: KUBECONFIG not set" >&2
    exit 2
fi

if [[ -z "${AWS_REGION:-}" ]]; then
    echo "SKIP: AWS_REGION not set" >&2
    exit 2
fi

if ! command -v aws &>/dev/null; then
    echo "SKIP: aws CLI not available" >&2
    exit 2
fi

# Get cluster infrastructure ID
declare infraID
infraID=$(oc get infrastructure cluster -o jsonpath='{.status.infrastructureName}' 2>/dev/null)
if [[ -z "${infraID}" ]]; then
    echo "FAIL: could not determine cluster infrastructure ID" >&2
    exit 1
fi
echo "Cluster infrastructure ID: ${infraID}"

# Get VPC ID using the infrastructure ID
declare vpcID
vpcID=$(aws ec2 describe-vpcs \
    --region "${AWS_REGION}" \
    --filters "Name=tag:kubernetes.io/cluster/${infraID},Values=owned" \
    --query 'Vpcs[0].VpcId' \
    --output text 2>/dev/null)
if [[ -z "${vpcID}" || "${vpcID}" == "None" ]]; then
    echo "FAIL: could not determine VPC ID for cluster ${infraID}" >&2
    exit 1
fi
echo "VPC ID: ${vpcID}"

# Get worker security group
declare sgID
sgID=$(aws ec2 describe-security-groups \
    --region "${AWS_REGION}" \
    --filters "Name=tag:kubernetes.io/cluster/${infraID},Values=owned" \
               "Name=tag:Name,Values=*worker*" \
    --query 'SecurityGroups[0].GroupId' \
    --output text 2>/dev/null)
if [[ -z "${sgID}" || "${sgID}" == "None" ]]; then
    # Fallback: try to find any worker SG
    sgID=$(aws ec2 describe-security-groups \
        --region "${AWS_REGION}" \
        --filters "Name=tag:kubernetes.io/cluster/${infraID},Values=owned" \
        --query 'SecurityGroups[?contains(GroupName, `worker`)].GroupId | [0]' \
        --output text 2>/dev/null)
fi
if [[ -z "${sgID}" || "${sgID}" == "None" ]]; then
    echo "FAIL: could not find worker security group for cluster ${infraID}" >&2
    exit 1
fi
echo "Worker security group: ${sgID}"

# Add ingress rules for Storage Scale ports
# Port 12345 - GPFS daemon
aws ec2 authorize-security-group-ingress \
    --region "${AWS_REGION}" \
    --group-id "${sgID}" \
    --protocol tcp \
    --port 12345 \
    --source-group "${sgID}" 2>/dev/null || echo "Rule for port 12345 may already exist"

# Port 1191 - GPFS quorum
aws ec2 authorize-security-group-ingress \
    --region "${AWS_REGION}" \
    --group-id "${sgID}" \
    --protocol tcp \
    --port 1191 \
    --source-group "${sgID}" 2>/dev/null || echo "Rule for port 1191 may already exist"

# Port range 60000-61000 - GPFS ephemeral
aws ec2 authorize-security-group-ingress \
    --region "${AWS_REGION}" \
    --group-id "${sgID}" \
    --protocol tcp \
    --port 60000-61000 \
    --source-group "${sgID}" 2>/dev/null || echo "Rule for ports 60000-61000 may already exist"

echo "PASS: AWS security groups configured for Storage Scale"
exit 0
true
