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
* **S**

