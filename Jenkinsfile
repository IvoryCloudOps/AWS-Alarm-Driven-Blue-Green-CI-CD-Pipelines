// Requirements on the Jenkins agent: git, python3 (+venv), docker, aws cli v2, jq, trivy, curl.
// AWS access: attach an IAM instance/task role to the agent, or wrap stages with
// withCredentials([...]) / the AWS Credentials plugin.

// Publishes to the alerts SNS topic. A notification failure is logged but never changes
// the build result.
def notifySns(String subject, String message) {
    withEnv(["NOTIFY_SUBJECT=${subject.take(100)}", "NOTIFY_MESSAGE=${message}"]) {
        sh '''
            if ! ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text) \
                || ! aws sns publish \
                    --topic-arn "arn:aws:sns:$AWS_REGION:$ACCOUNT_ID:$SNS_TOPIC_NAME" \
                    --subject "$NOTIFY_SUBJECT" \
                    --message "$NOTIFY_MESSAGE" >/dev/null; then
                echo "WARNING: failed to publish SNS notification"
            fi
        '''
    }
}

pipeline {
    agent any

    parameters {
        choice(
            name: 'FAULT_INJECTION',
            choices: ['none', 'unhealthy', 'http-errors'],
            description: '''Rehearse a failed deployment. unhealthy: /health returns 500, so green never
gets production traffic. http-errors: /health passes and traffic shifts to green, then / returns 500
during the bake until the 5XX alarm makes ECS fail back to blue.'''
        )
    }

    options {
        timestamps()
        disableConcurrentBuilds()
        timeout(time: 60, unit: 'MINUTES')
        buildDiscarder(logRotator(numToKeepStr: '20'))
    }

    environment {
        AWS_REGION        = 'us-east-2'
        AWS_DEFAULT_REGION = 'us-east-2'
        ECR_REPOSITORY    = 'ivorycloud-delivery'
        ECS_CLUSTER       = 'blue-green-delivery-cluster'
        ECS_SERVICE       = 'ivorycloud-delivery-service'
        TASK_FAMILY       = 'ivorycloud-delivery'
        ALB_NAME          = 'blue-green-delivery-alb'
        BAKE_TIMEOUT_MIN  = '15'
        SNS_TOPIC_NAME    = 'blue-green-delivery-alerts'
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm
                script {
                    env.IMAGE_TAG = sh(script: 'git rev-parse HEAD', returnStdout: true).trim()
                    env.AWS_ACCOUNT_ID = sh(
                        script: 'aws sts get-caller-identity --query Account --output text',
                        returnStdout: true
                    ).trim()
                    env.ECR_REGISTRY = "${env.AWS_ACCOUNT_ID}.dkr.ecr.${env.AWS_REGION}.amazonaws.com"
                    env.IMAGE_URI = "${env.ECR_REGISTRY}/${env.ECR_REPOSITORY}:${env.IMAGE_TAG}"
                }
                echo "Image: ${env.IMAGE_URI}"
            }
        }

        stage('Validate Application') {
            steps {
                sh '''
                    python3 -m venv .venv
                    . .venv/bin/activate
                    pip install --upgrade pip
                    pip install -r app/requirements.txt
                    python -m py_compile app/app.py
                    cd app
                    python - <<'EOF'
from app import app
client = app.test_client()
r = client.get("/health")
assert r.status_code == 200 and r.get_json()["status"] == "healthy", r.data
assert client.get("/").status_code == 200
print("smoke tests passed")
EOF
                '''
            }
        }

        stage('Build Docker Image') {
            steps {
                sh 'docker build -t "$IMAGE_URI" ./app'
            }
        }

        stage('Scan Image') {
            steps {
                sh '''
                    trivy image \
                        --exit-code 1 \
                        --ignore-unfixed \
                        --severity CRITICAL,HIGH \
                        "$IMAGE_URI"
                '''
            }
        }

        stage('Push to ECR') {
            steps {
                // ECR tags are immutable, so skip the push if this commit was already pushed.
                sh '''
                    aws ecr get-login-password --region "$AWS_REGION" \
                        | docker login --username AWS --password-stdin "$ECR_REGISTRY"

                    if aws ecr describe-images --repository-name "$ECR_REPOSITORY" \
                        --image-ids imageTag="$IMAGE_TAG" >/dev/null 2>&1; then
                        echo "Tag $IMAGE_TAG already exists in ECR; skipping push."
                    else
                        docker push "$IMAGE_URI"
                    fi
                '''
            }
        }

        stage('Register Task Definition') {
            steps {
                script {
                    env.PREVIOUS_TASK_DEF = sh(
                        script: '''aws ecs describe-services --cluster "$ECS_CLUSTER" --services "$ECS_SERVICE" \
                                   --query 'services[0].taskDefinition' --output text''',
                        returnStdout: true
                    ).trim()

                    env.NEW_TASK_DEF = sh(
                        script: '''
                            aws ecs describe-task-definition --task-definition "$PREVIOUS_TASK_DEF" \
                                --query taskDefinition > current-task-definition.json

                            # FAULT_INJECTION is always cleared, and only set for a failed-deployment drill.
                            jq --arg IMAGE "$IMAGE_URI" --arg FAULT "${FAULT_INJECTION:-none}" '
                                del(.taskDefinitionArn, .revision, .status, .requiresAttributes,
                                    .compatibilities, .registeredAt, .registeredBy)
                                | .containerDefinitions[0].image = $IMAGE
                                | .containerDefinitions[0].environment =
                                    ([(.containerDefinitions[0].environment // [])[]
                                      | select(.name != "FAULT_INJECTION" and .name != "SIMULATE_UNHEALTHY")]
                                     + (if $FAULT != "none"
                                        then [{name: "FAULT_INJECTION", value: $FAULT}]
                                        else [] end))
                            ' current-task-definition.json > new-task-definition.json

                            aws ecs register-task-definition \
                                --cli-input-json file://new-task-definition.json \
                                --query 'taskDefinition.taskDefinitionArn' --output text
                        ''',
                        returnStdout: true
                    ).trim()
                }
                echo "Previous task definition: ${env.PREVIOUS_TASK_DEF}"
                echo "New task definition:      ${env.NEW_TASK_DEF}"
            }
        }

        stage('Deploy Green') {
            steps {
                script { env.DEPLOY_STARTED = 'true' }
                sh '''
                    aws ecs update-service \
                        --cluster "$ECS_CLUSTER" \
                        --service "$ECS_SERVICE" \
                        --task-definition "$NEW_TASK_DEF" >/dev/null
                '''
            }
        }

        stage('Validate Deployment') {
            steps {
                sh '''
                    # Wait for the green tasks to be running and healthy.
                    for i in $(seq 1 40); do
                        read -r RUNNING DESIRED STATE < <(aws ecs describe-services \
                            --cluster "$ECS_CLUSTER" --services "$ECS_SERVICE" \
                            --query "services[0].deployments[?taskDefinition=='$NEW_TASK_DEF'] | [0].[runningCount,desiredCount,rolloutState]" \
                            --output text)
                        echo "green: running=$RUNNING desired=$DESIRED rollout=$STATE"
                        [ "$STATE" = "FAILED" ] && { echo "Deployment failed"; exit 1; }
                        [ "$RUNNING" = "$DESIRED" ] && [ "$RUNNING" != "0" ] && break
                        [ "$i" = "40" ] && { echo "Timed out waiting for green tasks"; exit 1; }
                        sleep 15
                    done

                    # ALB health check.
                    ALB_DNS=$(aws elbv2 describe-load-balancers --names "$ALB_NAME" \
                        --query 'LoadBalancers[0].DNSName' --output text)
                    echo "$ALB_DNS" > alb_dns.txt
                    curl --fail --silent --show-error --retry 10 --retry-delay 6 --retry-all-errors \
                        "http://$ALB_DNS/health"
                '''
            }
        }

        stage('Bake Period') {
            steps {
                // ECS keeps the deployment IN_PROGRESS through the bake time configured on the
                // service, with blue still running. The service's CloudWatch alarms (unhealthy
                // targets, target 5XX) decide rollback: ECS shifts traffic back to blue and marks
                // the rollout FAILED. Jenkins only probes and reports, so it never races ECS.
                // The probes also give the 5XX alarm data when there is no real traffic.
                sh '''
                    ALB_DNS=$(cat alb_dns.txt)
                    END=$(( $(date +%s) + BAKE_TIMEOUT_MIN * 60 ))
                    while [ "$(date +%s)" -lt "$END" ]; do
                        STATE=$(aws ecs describe-services --cluster "$ECS_CLUSTER" --services "$ECS_SERVICE" \
                            --query "services[0].deployments[?taskDefinition=='$NEW_TASK_DEF'] | [0].rolloutState" \
                            --output text)
                        CODES=""
                        for i in 1 2 3 4 5; do
                            CODES="$CODES $(curl -s -o /dev/null -m 5 -w '%{http_code}' "http://$ALB_DNS/")"
                        done
                        HEALTH=$(curl -s -o /dev/null -m 5 -w '%{http_code}' "http://$ALB_DNS/health")
                        echo "rollout=$STATE /:$CODES /health: $HEALTH"
                        [ "$STATE" = "COMPLETED" ] && { echo "Bake complete"; exit 0; }
                        [ "$STATE" = "FAILED" ] && { echo "Rollout failed: ECS rolled back to blue"; exit 1; }
                        sleep 15
                    done
                    echo "Bake period timed out"; exit 1
                '''
            }
        }
    }

    post {
        success {
            echo "Deployed ${env.IMAGE_URI} (${env.NEW_TASK_DEF}) successfully."
            notifySns(
                "SUCCESS: ${env.JOB_NAME} #${env.BUILD_NUMBER}",
                """Deployment succeeded.

Job:             ${env.JOB_NAME} #${env.BUILD_NUMBER}
Build URL:       ${env.BUILD_URL ?: 'n/a'}
Image:           ${env.IMAGE_URI}
Task definition: ${env.NEW_TASK_DEF}
Previous:        ${env.PREVIOUS_TASK_DEF}"""
            )
        }

        failure {
            script {
                echo "Pipeline failed."
                def rollback = 'not needed (failed before deploy)'
                if (env.DEPLOY_STARTED == 'true' && env.PREVIOUS_TASK_DEF) {
                    def current = sh(
                        script: '''aws ecs describe-services --cluster "$ECS_CLUSTER" --services "$ECS_SERVICE" \
                                   --query 'services[0].taskDefinition' --output text''',
                        returnStdout: true
                    ).trim()

                    if (current == env.PREVIOUS_TASK_DEF) {
                        // The ECS alarm or circuit breaker already rolled the service back.
                        echo "ECS already rolled back to ${env.PREVIOUS_TASK_DEF}"
                        def reason = sh(
                            script: '''
                                ARN=$(aws ecs list-service-deployments --cluster "$ECS_CLUSTER" --service "$ECS_SERVICE" \
                                    --query "serviceDeployments[?starts_with(status, 'ROLLBACK')] | [0].serviceDeploymentArn" \
                                    --output text) \
                                && aws ecs describe-service-deployments --service-deployment-arns "$ARN" \
                                    --query "serviceDeployments[0].[statusReason, join(', ', alarms.triggeredAlarmNames || ['none'])]" \
                                    --output text | awk -F '\\t' '{ print $1 " Triggered alarms: " $2 }' \
                                || true
                            ''',
                            returnStdout: true
                        ).trim()
                        rollback = "ECS automatic rollback to ${env.PREVIOUS_TASK_DEF}"
                        if (reason) {
                            rollback += " (${reason})"
                        }
                    } else {
                        echo "Rolling back to ${env.PREVIOUS_TASK_DEF}"
                        sh '''
                            aws ecs update-service \
                                --cluster "$ECS_CLUSTER" \
                                --service "$ECS_SERVICE" \
                                --task-definition "$PREVIOUS_TASK_DEF" >/dev/null
                        '''
                        rollback = "Jenkins rollback to ${env.PREVIOUS_TASK_DEF}"
                    }

                    def healthy = sh(
                        script: '''
                            aws ecs wait services-stable --cluster "$ECS_CLUSTER" --services "$ECS_SERVICE"
                            ALB_DNS=$(aws elbv2 describe-load-balancers --names "$ALB_NAME" \
                                --query 'LoadBalancers[0].DNSName' --output text)
                            for path in /health /; do
                                curl --fail --silent --show-error --retry 5 --retry-delay 6 --retry-all-errors \
                                    -o /dev/null "http://$ALB_DNS$path" || exit 1
                            done
                        ''',
                        returnStatus: true
                    ) == 0
                    rollback += healthy ? '; service stable and healthy again' : '; WARNING: service not confirmed healthy'
                }
                notifySns(
                    "FAILURE: ${env.JOB_NAME} #${env.BUILD_NUMBER}",
                    """Pipeline failed.

Job:       ${env.JOB_NAME} #${env.BUILD_NUMBER}
Build URL: ${env.BUILD_URL ?: 'n/a'}
Commit:    ${env.IMAGE_TAG ?: 'n/a'}
Simulated: ${(params.FAULT_INJECTION ?: 'none') == 'none' ? 'no' : "yes (FAULT_INJECTION=${params.FAULT_INJECTION})"}
Rollback:  ${rollback}"""
                )
            }
        }

        always {
            sh 'docker logout "$ECR_REGISTRY" || true'
            sh 'docker image rm "$IMAGE_URI" || true'
            cleanWs()
        }
    }
}
