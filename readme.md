# AWS Systems Manager — Agentless Fleet Deployment

Deployment of the Datadog Agent across an EC2 fleet using AWS Systems Manager (SSM), with zero SSH access and secrets managed through Parameter Store.

## Summary

EC2 instances are managed entirely through SSM (IAM-based access, no SSH). The Datadog Agent is installed fleet-wide via a custom SSM Command Document executed through Run Command. The Datadog API key is stored as a `SecureString` in Parameter Store and retrieved at runtime — never hardcoded or logged.

## IAM Policy (attached to instance role)

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["ssm:GetParameter"],
      "Resource": "arn:aws:ssm:*:*:parameter/monitoring/*"
    }
  ]
}
```

## SSM Command Document

Full file: [`InstallMonitoringAgent.json`](InstallMonitoringAgent.json)

```json
{
  "schemaVersion": "2.2",
  "description": "Install Datadog Agent and configure it with an API key retrieved securely from Parameter Store",
  "parameters": {},
  "mainSteps": [
    {
      "action": "aws:runShellScript",
      "name": "InstallDatadogAgent",
      "inputs": {
        "runCommand": [
          "#!/bin/bash",
          "set -e",
          "DD_API_KEY=$(aws ssm get-parameter --name '/monitoring/api-key' --with-decryption --query 'Parameter.Value' --output text --region us-east-1)",
          "DD_API_KEY=\"$DD_API_KEY\" DD_SITE=\"datadoghq.com\" bash -c \"$(curl -L https://s3.amazonaws.com/dd-agent/scripts/install_script_agent7.sh)\"",
          "sudo systemctl status datadog-agent --no-pager"
        ]
      }
    }
  ]
}
```

## Deployment

```bash
aws ssm send-command \
  --document-name "InstallMonitoringAgent" \
  --targets "Key=tag:Environment,Values=dev" \
  --comment "Deploy Datadog agent fleet-wide"
```

## Results

**Fleet Manager — instances managed by SSM, no SSH:**
![Fleet Manager](./Screenshot%202026-09-14%20172714.png)

**Datadog Dashboard — host reporting after agent install:**
![Datadog Dashboard](./Screenshot%202026-09-16%20081940.png)

## Security Notes

- No SSH keys, no inbound port 22 — all access is IAM-authorized through SSM.
- API key is never hardcoded or committed; fetched at runtime from Parameter Store.
- Every Run Command execution is logged, providing an audit trail.

