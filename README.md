# AWS Alarm-Driven Blue/Green CI/CD Pipelines🚨☁️
**Status**: Complete✅ — successful deployment, triggered alarms, and rollback exercise validated <br>
**Environment**: AWS us-east-2 · Lab deployment (current uptime not asserted) <br>
**Focus**: Jenkins · GitHub Actions · Terraform · Docker · Trivy · Amazon ECR · ECS/Fargate · CloudWatch

Designed and tested an AWS container-delivery platform with **two independent CI/CD pipelines**: Jenkins for application releases and GitHub Actions for controlled Terraform infrastructure changes. The application pipeline uses immutable container images and ECS-native blue/green rollback; the infrastructure pipeline uses OIDC, reviewable plans, and approval-gated applies.

📖 [Read the full engineering case study on Medium](https://medium.com/@ivorycloudops/engineering-alarm-driven-blue-green-ci-cd-pipelines-with-jenkins-ecs-and-terraform-%EF%B8%8F-06adb0b553c9?postPublishedType=initial) — design rationale, architecture, Jenkins deployment evidence, failure/rollback testing, and Terraform change controls.

## 1. Business Problem🏢

Application releases needed repeatable validation, image scanning, and recovery when a new version became unhealthy. Shared AWS infrastructure needed a separate change-control process so application builds could not silently modify the Terraform-managed foundation, and pull requests could not automatically apply changes.

## 2. Architecture🏗️

**Application CI/CD & ECS Blue/Green Deployment**

![Alarm-Driven Blue/Green CI/CD Pipeline Architecture](https://miro.medium.com/v2/resize:fit:1100/format:webp/1*4lhJ-j05V8nXNKYH8uJLXw.png)

**Application delivery:** GitHub checkout → Jenkins on EC2 → Flask smoke tests → Docker build → Trivy scan → immutable Amazon ECR image → ECS/Fargate deployment.

An internet-facing ALB routes HTTP traffic through two blue/green target groups to the active ECS task revision in private subnets. **CloudWatch rollback alarms drive ECS-native recovery; Jenkins checks deployment status and reports through SNS**. The ECS service has one steady-state desired task, so this lab does not claim active-active multi-AZ application capacity.

## GitHub Actions & Terraform Infrastructure CI/CD

![AWS Cloud Architecture Diagram](https://miro.medium.com/v2/resize:fit:1100/format:webp/1*s8RKU_GRVtMOEwHhxUZ_6Q.png)

**Infrastructure delivery:** Pull requests run Terraform formatting, validation, TFLint, **report-only Checkov**, and a read-only plan for review. Eligible pushes to main can run an apply only after detected changes, TF_APPLY_ENABLED=true, protected production approval, and a re-plan/change-action digest comparison. GitHub OIDC assumes distinct Plan and Apply roles; a separately bootstrapped, versioned S3 backend uses native lockfiles.

## 3. Key Decisions & Why🤔
   
- **Independent delivery pipelines:** Jenkins handles application revisions; GitHub Actions manages infrastructure changes.
  
- **Alarm-driven ECS-native rollback:** Real target-5XX alarm and SNS notifications corroborate ECS rollback, while Jenkins verifies the recovered revision.
  
- **Immutable ECR images:** Full commit-SHA tags provide traceable release artifacts.
  
- **Role-based temporary AWS credentials:** Jenkins uses an EC2 instance profile; GitHub Actions uses OIDC and separate planning/applying IAM roles.
  
- **Reviewed Terraform changes:** PR planning, controlled production approval, and state locking reduce accidental concurrent or unreviewed infrastructure edits.
  
**Validation:** Jenkins build **#12** completed all application stages. Build #14 introduced HTTP 500s; the CloudWatch target-5XX alarm entered ALARM, ECS rolled back, and Jenkins confirmed the previous task definition. SNS sent the alarm and pipeline notifications. An earlier, separate unhealthy-target alarm also showed ALARM → OK transitions. GitHub Actions evidence includes planning, production approval, and validation failure blocking downstream work. **No zero-downtime claim is made**.

[See the testing screenshots and technical explanation on Medium](https://medium.com/@ivorycloudops/engineering-alarm-driven-blue-green-ci-cd-pipelines-with-jenkins-ecs-and-terraform-%EF%B8%8F-06adb0b553c9?postPublishedType=repub)

## 4. What I'd Do Differently at Production Scale
   
- Add HTTPS/ACM, ALB access logging, and stronger IAM/network boundaries.
  
- Move beyond a single long-lived Jenkins controller toward resilient controllers and ephemeral build agents.
  
- Promote vetted Checkov findings from soft-fail reports to enforced policies and expand application testing.
  
- Test a separate green listener before production traffic shifting and tune bake periods/alarms to observed traffic.
  
- Revisit the single NAT Gateway and one-task baseline against availability and recovery requirements.
  
**Source files: Jenkinsfile** · [Infrastructure workflow](.github/workflows/infrastructure.yml) · [`terraform/`](terraform/) · [`app/`](app/)

**Detailed documentation:** [Medium engineering case study](https://medium.com/@ivorycloudops/engineering-alarm-driven-blue-green-ci-cd-pipelines-with-jenkins-ecs-and-terraform-%EF%B8%8F-06adb0b553c9?postPublishedType=repub)
