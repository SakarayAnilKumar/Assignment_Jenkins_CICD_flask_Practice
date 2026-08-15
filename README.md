# End-to-End CI/CD Pipeline Architecture & Operations Manual

This document provides a comprehensive, step-by-step technical guide for configuring, executing, maintaining, and troubleshooting the Jenkins CI/CD pipeline for the Student Registration Application hosted on AWS EC2.

---

## 1. Executive Summary & Architecture Overview

The primary objective of this pipeline is to automate the build, containerization, deployment, and validation lifecycle of the Student Registration microservice. 

### Key Objectives
* **Automation:** Eliminate manual SSH and Docker execution steps.
* **Consistency:** Ensure identical container artifacts move through build, test, and deployment phases.
* **Reliability:** Execute automated HTTP health checks post-deployment to guarantee application stability before concluding the build.
* **Notification:** Notify stakeholders immediately with precise failure stage and commit metadata upon pipeline failure.

### Infrastructure Architecture

```
[ Developer Commit ] ──> [ Git Repository ]
                                │
                                ▼
                   [ Windows Jenkins Host ]
                                │
    ┌───────────────────────────┴───────────────────────────┐
    │ 1. Git Checkout                                       │
    │ 2. Docker Image Build                                 │
    │ 3. Push Artifact to AWS ECR                           │
    └───────────────────────────┬───────────────────────────┘
                                │ (SSH / WinCMD Orchestration)
                                ▼
                      [ AWS EC2 Instance ]
    ┌───────────────────────────────────────────────────────┐
    │ 4. Pull Image from ECR                                │
    │ 5. Stop/Remove Stale Container                        │
    │ 6. Run Container (Port 5000, MONGO_URI Env Injection) │
    └───────────────────────────┬───────────────────────────┘
                                │
                                ▼
                [ Health Check & Email Alerts ]
```

---

## 2. Environment & Tooling Specifications

| System Component | Host / Location | Environment / Binary Path | Responsibilities |
| :--- | :--- | :--- | :--- |
| **Jenkins Master** | Windows Server | `C:\ProgramData\Jenkins\...` | Pipeline orchestration, credential management, triggering remote steps. |
| **Git Bash Engine** | Windows Server | `C:\Program Files\Git\bin\bash.exe` | Tunneling single-line SSH and Bash commands from Windows `cmd.exe`. |
| **Target Host** | AWS EC2 (Linux) | `13.223.96.128` | Hosts the application container runtime. |
| **Container Engine** | AWS EC2 (Linux) | `/usr/bin/docker` | Executes container lifecycle commands (`pull`, `stop`, `rm`, `run`). |
| **Registry** | AWS ECR | `316412036553.dkr.ecr.us-east-1.amazonaws.com` | Private Docker image artifact storage. |
| **Database** | MongoDB Atlas / Cloud | External URI | Persistent backend data storage. |

---

---

## 3. IAM Configuration: User, Role & Access Keys Setup

To allow Jenkins and the EC2 instance to interact with AWS ECR, configure the following IAM credentials in the AWS Management Console:

### Step 3.1: Create IAM User for Jenkins (`ECR-Access-ID`)
1. Open the **AWS IAM Console** and navigate to **Users** > **Create user**.
2. Set the username (e.g., `jenkins-ecr-builder`).
3. Under **Permissions options**, select **Attach policies directly**.
4. Search for and attach the **`AmazonEC2ContainerRegistryPowerUser`** managed policy (provides permission to authenticate, build, pull, and push images to ECR).
5. Complete user creation.

### Step 3.2: Generate AWS Access Keys
1. Select the newly created user (`jenkins-ecr-builder`).
2. Navigate to the **Security credentials** tab.
3. Scroll down to **Access keys** and click **Create access key**.
4. Select **Command Line Interface (CLI)** as the use case, acknowledge the recommendation, and click **Next**.
5. Copy or download the **Access Key ID** and **Secret Access Key**.
6. In Jenkins, store these credentials under **Manage Jenkins > Credentials** as an AWS Credential type named **`ECR-Access-ID`**.

### Step 3.3: (Optional) Create EC2 IAM Role for Instance ECR Access
If you prefer EC2 instance-level authentication over passing credentials over SSH:
1. Navigate to **IAM** > **Roles** > **Create role**.
2. Select **AWS service** as trusted entity type and **EC2** as the use case.
3. Attach the **`AmazonEC2ContainerRegistryReadOnly`** policy.
4. Name the role (e.g., `EC2-ECR-ReadOnly-Role`) and create it.
5. In the **EC2 Console**, select your target instance (`13.223.96.128`) > **Actions** > **Security** > **Modify IAM role**, and attach `EC2-ECR-ReadOnly-Role`.

---

## 4. Jenkins Credentials Setup

The pipeline relies on four specific Jenkins Credentials. Configure these under **Jenkins > Manage Jenkins > Credentials**:

1. **`ec2-ssh-key-file`** *(Secret file)*: Private `.pem` key used to authenticate SSH sessions into the target EC2 instance.
2. **`ECR-Access-ID`** *(AWS Credentials / Access Key Pair)*: AWS Access Key and Secret Key authorized to generate ECR authentication tokens via `aws ecr get-login-password`.
3. **`MONGO_URI`** *(Secret text)*: Full database connection string including query parameters (e.g., `mongodb+srv://<user>:<password>@cluster.mongodb.net/students_db?retryWrites=true&w=majority`).
4. **`anilirctc26-email`** *(SMTP / Mailer)*: Configuration for the `emailext` plugin to deliver HTML notifications.

---

## 5. Operational Prerequisites & Constraints

To prevent common pipeline runtime failures, the following platform constraints must be enforced:

* **Windows Command Execution Constraints (`bat`):** Windows `cmd.exe` breaks single-quoted multi-line SSH string payloads into separate local terminal calls. All remote SSH sequences invoked via `bat` **must** be executed on a single line using `&&` chain operator syntax.
* **Variable Escaping Rules:** Windows batch treats `%` characters as variable delimeters. Percent signs used in strings must be escaped (e.g., `%%{http_code}`).
* **Port Inbound Access:** Port `5000` must be exposed on the EC2 Security Group inbound rules to allow the Jenkins host to reach `http://%EC2_HOST%:5000/health`.
* **Database URI Formatting:** Special characters in `MONGO_URI` (such as `&` or `?`) must remain completely enclosed inside single quotes within the Docker command string to avoid Windows shell command splitting.

## 6. Detailed Pipeline Stage Breakdown

1. **Checkout Source:** Pulls the latest application source code and `Dockerfile` from the Git repository branch into the local Jenkins workspace on the Windows host.
2. **Build & Push Docker Image:** Authenticates the Windows Jenkins node with AWS ECR using temporary AWS credentials, tags the image using the current Jenkins `BUILD_NUMBER`, and pushes the built container artifact to the central ECR registry.
3. **Deploy to EC2 Instance:** Opens an SSH session from Windows Git Bash to the target EC2 host (`13.223.96.128`). Runs a single-line chained shell script on Linux to authenticate to ECR, stop/remove existing containers, pull the newly pushed image tag, and start the container with environment parameters.
4. **Validate Application Health:** Executes a native PowerShell script on the Jenkins master to poll `http://13.223.96.128:5000/health`. If the HTTP response is 200 OK within 10 seconds, the stage passes. If non-200 or connection failure occurs, the script throws `exit 1` to fail the build.

---

## 7. Post-Actions & Notification Engine

The `post` execution block monitors the outcome of the entire pipeline lifecycle and executes notification tasks:

* **Always Block:** Emits a log confirmation upon pipeline termination regardless of success or failure state.
* **Success Block:** Dispatches an HTML status email containing the Git Commit SHA, pushed Image Tag, and build URL.
* **Failure Block:** Dynamically identifies the exact stage that threw the error via `${env.STAGE_NAME}`, captures build identifiers, and formats an HTML email warning alerting operators to inspect the job logs.

---

## 8. Comprehensive Troubleshooting Guide

| Issue / Error Symptom | Root Cause | Resolution Step |
| :--- | :--- | :--- |
| `'export' is not recognized as an internal or external command` | Multi-line string inside `bat` was split by Windows `cmd.exe`, attempting to execute Bash commands locally in Windows Command Prompt. | Ensure the SSH payload inside the `bat` block is formatted as a single line joined with `&&` operators. |
| `unexpected EOF while looking for matching quote` | Unescaped single quotes `'` or double quotes `"` inside the nested SSH script payload. | Escape quotes correctly (`'` or `"`) or use standard variable substitution without shell interpolation. |
| `echo.: command not found` | Using Windows CMD syntax (`echo.`) inside a Linux/Bash shell block. | Replace `echo.` with Linux standard `echo ''` or `Write-Host` in PowerShell. |
| Health check timeouts / connection refused | EC2 Security Group is blocking inbound TCP traffic on port `5000` from the Jenkins IP address. | Add an Inbound Rule in AWS EC2 Console allowing TCP port `5000` from the Jenkins host CIDR block. |
| `Error response from daemon: No such container` | Docker attempt to stop/remove a container that does not currently exist on the host. | Handled gracefully using `docker stop container || true` and `docker rm container || true`. |

## 9. Test Results

### Successful Pipeline

#### Pipeline Image
![Successful Pipeline](path/to/successful-pipeline-image.png)

#### Email Confirmation
![Successful Email Confirmation](path/to/successful-email-image.png)

#### Application Testing
![Application Testing Success](path/to/application-testing-success-image.png)

---

### Failed Pipeline

#### Pipeline Image
![Failed Pipeline](path/to/failed-pipeline-image.png)

#### Email Confirmation
![Failed Email Confirmation](path/to/failed-email-image.png)

#### Application Testing
![Application Testing Failure](path/to/application-testing-failure-image.png)



