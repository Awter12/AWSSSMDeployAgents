# AWS Systems Manager (SSM) — Agentless Fleet Deployment

Deploy and manage a monitoring agent across an EC2 fleet (Windows & Linux) using **AWS Systems Manager Run Command** and **Parameter Store** — with zero SSH access required.

## Overview

This project demonstrates a secure, agentless deployment pipeline on AWS:

- EC2 instances are managed remotely through the **SSM Agent** (no SSH keys, no open port 22).
- Secrets (API keys) are stored and retrieved securely via **Parameter Store** (`SecureString`), never exposed in logs or code.
- A custom **SSM Command Document** installs and starts a monitoring agent as a `systemd` service.
- Deployment is executed fleet-wide via **Run Command**, targeting instances by tag.

## Architecture

```
                ┌────────────────────┐
                │   IAM Role          │
                │ (SSM + Parameter    │
                │  Store permissions) │
                └─────────┬───────────┘
                          │ attached to
                          ▼
   ┌───────────────────────────────────────┐
   │        EC2 Instances (Fleet)           │
   │  ┌─────────────┐   ┌─────────────┐    │
   │  │ SSM Agent    │   │ SSM Agent    │    │
   │  │ (Instance 1) │   │ (Instance 2) │    │
   │  └──────┬───────┘   └──────┬───────┘    │
   └─────────┼──────────────────┼───────────┘
             │                  │
             ▼                  ▼
     ┌──────────────────────────────────┐
     │   AWS Systems Manager             │
     │   • Fleet Manager (visibility)    │
     │   • Run Command (executes doc)    │
     │   • Parameter Store (secrets)     │
     └──────────────────────────────────┘
```



## — SSM Setup

**Goal:** Get EC2 instances managed by SSM (no SSH).

### 1. IAM Role with SSM Permissions

Created an IAM role attached to the EC2 instance profile with the AWS-managed policy `AmazonSSMManagedInstanceCore`, which grants the permissions the SSM Agent needs to register with the service and receive commands.

Additionally, an inline policy was attached to allow reading the specific application secret from Parameter Store:

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

> Note: if the parameter is encrypted with a **customer-managed KMS key** (not the AWS-managed default), the role also needs `kms:Decrypt` on that key.

**Screenshot:** ![IAM Role Setup](./Screenshot%202026-09-14%20172714.png)

### 2. Launch EC2 with SSM Agent

Launched an EC2 instance (Amazon Linux 2/2023, which ships with the SSM Agent pre-installed) and attached the IAM role/instance profile created above. No key pair / SSH inbound rule was required for management.



### 3. Verify in Fleet Manager

Confirmed the instance appeared as **Managed** in **Systems Manager → Fleet Manager**, with a "Ping status: Online" — confirming the SSM Agent successfully registered without any SSH connection.

**Screenshot:** `screenshots/03-fleet-manager.png`

### 4. Store API Key in Parameter Store

Created a `SecureString` parameter to hold the agent's API key, keeping secrets out of code, AMIs, and Run Command history.

- **Name:** `/monitoring/api-key`
- **Type:** `SecureString`
- **Value:** (redacted)



---

## — Remote Deployment

**Goal:** Deploy the monitoring agent without SSH.

### 1. Create SSM Document

Authored a custom **Command document** (`InstallMonitoringAgent`) defining the install steps. Built via the console using the JSON editor, `schemaVersion 2.2`.

Key design decisions:
- Uses `aws:runShellScript` for Linux targets (a `aws:runPowerShellScript` variant would be used for Windows targets).
- Retrieves the API key from Parameter Store at runtime rather than baking it into the script.
- Registers the agent as a `systemd` service so it runs persistently and can be verified with standard OS tooling (`systemctl status`).


The full document is available in [`docs/InstallMonitoringAgent.json`](docs/InstallMonitoringAgent.json).



### 2. Run Command to Install the Agent

Executed the document via **Systems Manager → Run Command**, targeting instances by tag (`Environment=dev`) rather than by instance ID, so the deployment scales to any instance with that tag without modifying the command.



### 3. Retrieve Secrets from Parameter Store

The `get-parameter --with-decryption` call inside the document (above) pulls the `SecureString` value at execution time. The value is:
- Never written to the console output or CloudWatch Logs
- Passed directly into the service's environment (`Environment=API_KEY=$API_KEY`)
- Only accessible because the **instance's IAM role** — not a human credential — has `ssm:GetParameter` permission



### 4. Verify Agent Running

Confirmed successful execution in **Run Command → Command history**, and inspected the per-instance output showing:
- API key retrieved successfully
- `monitoring-agent.service` reported as `active (running)`

**Screenshot:** `screenshots/08-agent-verified.png`

### 5. Multi-Instance Deployment

Re-ran the same Run Command against multiple instances matched by tag, demonstrating fleet-wide rollout from a single command execution — no per-instance manual work, no SSH.


