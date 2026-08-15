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

## 3. AWS Setup: ECR Repository, EC2 Instance, IAM & Docker Configuration

To allow Jenkins and the target EC2 instance to store, retrieve, and execute Docker container images, configure the AWS ECR Repository, EC2 Instance, Docker environment, and IAM credentials in the AWS Management Console:

### Step 3.1: Create AWS ECR Repository
1. Open the **AWS Management Console** and search for **Elastic Container Registry (ECR)**.
2. Under **Private registry**, select **Repositories** and click **Create repository**.
3. Set the repository visibility to **Private**.
4. Enter the **Repository name** (e.g., `student-registration`).
5. Under **Tag immutability**, select **Mutable** (allows overwriting build tags) or **Immutable** depending on your deployment strategy.
6. Enable **Scan on push** under **Image scan configuration** for vulnerability scanning.
7. Click **Create repository** and copy the generated ECR Repository URI (e.g., `316412036553.dkr.ecr.us-east-1.amazonaws.com/student-registration`).

<img width="1916" height="290" alt="image" src="https://github.com/user-attachments/assets/81f4fbe3-46b0-4034-b9c3-f5e7cbe48030" />

### Step 3.2: Launch AWS EC2 Instance & Configure Security Group
1. Open the **AWS EC2 Console** and click **Launch Instance**.
2. **Name:** Enter `Student-App-Server`.
3. **AMI:** Choose **Amazon Linux 2023** or **Ubuntu 22.04 LTS**.
4. **Instance Type:** Select `t2.micro` (or higher depending on workspace workload).
5. **Key Pair:** Select an existing `.pem` key pair or create a new one (e.g., `ec2-ssh-key.pem`) and download it for Jenkins SSH authentication.
6. **Network Settings (Security Group):**
   * Create a new Security Group named `student-app-sg`.
   * Add Inbound Rule 1: **SSH (Port 22)** — Source: `My IP` or `Jenkins Master IP` for secure remote pipeline orchestration.
   * Add Inbound Rule 2: **Custom TCP (Port 5000)** — Source: `Anywhere (0.0.0.0/0)` or `Jenkins Master IP` to allow health check validation and application access.
7. Click **Launch Instance** and note the assigned Public IP address (e.g., `13.223.96.128`).

<img width="1907" height="407" alt="image" src="https://github.com/user-attachments/assets/14d3dc1e-5ffc-4e16-92e0-5700f4712e34" />

### Step 3.3: Install Docker & Configure Prerequisites on EC2
Connect to your EC2 instance via SSH and run the following commands to install Docker, start the service, and set up user permissions:

```bash
# Update local package manager
sudo yum update -y   # Use 'sudo apt update -y' for Ubuntu

# Install Docker engine and AWS CLI
sudo yum install -y docker awscli   # Use 'sudo apt install -y docker.io awscli' for Ubuntu

# Start Docker daemon and enable it on boot
sudo systemctl start docker
sudo systemctl enable docker

# Add system user (ec2-user / ubuntu) to the docker group to run containers without sudo
sudo usermod -aG docker ec2-user

# Apply updated group permissions immediately
newgrp docker

# Verify Docker daemon functionality
docker --version
docker ps
```

<img width="1681" height="1016" alt="image" src="https://github.com/user-attachments/assets/c4e68312-c307-44c4-983e-a6d196977f40" />

### Step 3.4: Create EC2 IAM Role for Instance ECR Access
If you prefer EC2 instance-level authentication over passing credentials over SSH:
1. Navigate to **IAM** > **Roles** > **Create role**.
2. Select **AWS service** as trusted entity type and **EC2** as the use case.
3. Attach the **`AmazonEC2ContainerRegistryReadOnly`** policy.
4. Name the role (e.g., `EC2-ECR-ReadOnly-Role`) and create it.
5. In the **EC2 Console**, select your target instance (`13.223.96.128`) > **Actions** > **Security** > **Modify IAM role**, and attach `EC2-ECR-ReadOnly-Role`.

<img width="1882" height="881" alt="image" src="https://github.com/user-attachments/assets/0c45712c-4565-4d18-bbcd-260d5523b491" />


---

## 4. Jenkins Credentials Setup

The pipeline relies on four specific Jenkins Credentials. Configure these under **Jenkins > Manage Jenkins > Credentials**:

1. **`ec2-ssh-key-file`** *(Secret file)*: Private `.pem` key used to authenticate SSH sessions into the target EC2 instance.
2. **`ECR-Access-ID`** *(AWS Credentials / Access Key Pair)*: AWS Access Key and Secret Key authorized to generate ECR authentication tokens via `aws ecr get-login-password`.
3. **`MONGO_URI`** *(Secret text)*: Full database connection string including query parameters (e.g., `mongodb+srv://<user>:<password>@cluster.mongodb.net/students_db?retryWrites=true&w=majority`).
4. **`anilirctc26-email`** *(SMTP / Mailer)*: Configuration for the `emailext` plugin to deliver HTML notifications.

<img width="1676" height="522" alt="image" src="https://github.com/user-attachments/assets/ed3a688f-0c4f-46ee-a20c-decc401bc795" />

<img width="1777" height="632" alt="image" src="https://github.com/user-attachments/assets/35b90c6e-6c07-4c05-b343-e052e835e4a7" />


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

<img width="1902" height="882" alt="image" src="https://github.com/user-attachments/assets/5424fb11-414d-46e2-8d4e-0b8eca1d50b8" />

#### Email Confirmation

<img width="1507" height="665" alt="image" src="https://github.com/user-attachments/assets/0fbc71d3-5f88-46a2-8372-d31774a8ebb6" />


#### Application Testing

<img width="1832" height="687" alt="image" src="https://github.com/user-attachments/assets/5c335d57-9e17-4798-81f8-6635be5364bb" />


---

### Failed Pipeline

#### Pipeline Image

<img width="1892" height="902" alt="image" src="https://github.com/user-attachments/assets/3a9883cb-e812-4235-9387-4fa5fa0858ca" />

#### Email Confirmation

<img width="1542" height="667" alt="image" src="https://github.com/user-attachments/assets/cc3eabe2-e588-4723-8666-451babb4f18e" />



