# 🚀 AWS Blue/Green Container Delivery Platform

**Status:** In Progress

**Environment status:** Local Development

**Focus:** AWS • CI/CD • GitHub Actions • Terraform • Docker • Amazon ECR • ECS/Fargate • Blue/Green Deployments • CloudWatch

A hands-on DevOps and cloud engineering portfolio project focused on building a production-style delivery platform for safely moving application code from GitHub into AWS. The project is being built incrementally around automated testing, containerization, security scanning, versioned artifacts, controlled deployments, health validation, monitoring, and rollback.

---

## 🏢 The Business Problem

The fictional application team currently has no standardized release process. Application changes need a repeatable way to move from source control into AWS without relying on manual deployments, long-lived credentials, or blindly replacing the production workload.

The goal is to build a delivery platform that can validate a release before production, deploy a candidate version separately from the known-good version, monitor its health, and stop or reverse a failed deployment before it becomes a larger production incident.

---

## 🏗️ Architecture

The planned delivery flow is:

```text
GitHub
   |
   v
GitHub Actions
   |
   +--> Application Tests
   +--> Security Scans
   +--> Docker Build
   |
   v
Amazon ECR
   |
   v
Amazon ECS / Fargate
   |
   v
Application Load Balancer
   |
   +--> Blue Production Environment
   +--> Green Candidate Environment
   |
   v
Health Checks / Smoke Tests
   |
   v
CloudWatch Monitoring
   |
   +--> Successful Promotion
   └--> Failed Deployment / Rollback
```

Infrastructure and application delivery are intentionally separated:

```text
Infrastructure CI/CD
Terraform → GitHub Actions → AWS

Application CI/CD
Application Code → GitHub Actions → Docker → ECR → ECS
```

---

## 🧠 Key Decisions & Why

* **GitHub Actions as the primary CI/CD platform.** Keeps source control and pipeline automation together without adding Jenkins simply for tool count.
* **Separate infrastructure and application pipelines.** Application changes should not rebuild the VPC, load balancer, or other infrastructure every time code changes.
* **Docker + immutable image versions.** Releases will use identifiable image versions or commit-based tags instead of relying only on `latest`, making deployments and rollbacks traceable.
* **ECS/Fargate instead of Kubernetes.** The project needs production-style container delivery without adding unnecessary EKS/Kubernetes operational complexity.
* **GitHub OIDC instead of permanent AWS access keys.** GitHub Actions will eventually assume an AWS IAM role through temporary STS credentials rather than storing long-lived AWS credentials in GitHub.
* **Blue/Green deployment instead of direct replacement.** New versions will be deployed as a separate candidate environment and validated before replacing the known-good production version.
* **CloudWatch as the operational source of truth.** Deployment health, alarms, logs, and rollback signals will remain AWS-native, with Grafana added later only as a visualization layer.
* **The application stays intentionally simple.** The project is about delivery engineering, not application development. The current Flask app exists primarily to provide versioning, health checks, containerization, and controlled failure testing.

---

## 🚀 What I'd Do Differently at Production Scale

* **Separate AWS accounts for development, staging, and production** instead of keeping environments inside one account.
* **Stricter policy-as-code enforcement** for Terraform and container vulnerabilities once the pipeline is mature.
* **Expanded observability** with deeper distributed tracing, service-level indicators, and longer-term operational dashboards.
* **More sophisticated progressive delivery**, potentially including canary strategies based on workload requirements.
* **Centralized secrets and configuration governance** across multiple environments and applications.
* **Broader automated recovery workflows** beyond deployment rollback, including event-driven remediation for operational failures.

---

## Current Progress

Completed so far:

* Created the project repository structure
* Built the initial Python Flask application
* Added `/` and `/health` endpoints
* Verified the application locally on port `8080`
* Added Gunicorn
* Created the Dockerfile
* Installed and configured Docker Desktop
* Successfully built the first Docker image: `ivorycloud-delivery:v1`

Next step: run the Docker container locally and validate the application from inside the container.
