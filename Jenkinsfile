// Requirements on the Jenkins agent: git, python3 (+venv), docker, aws cli v2, jq, trivy, curl.
// AWS access: attach an IAM instance/task role to the agent, or wrap stages with
// withCredentials([...]) / the AWS Credentials plugin.
pipeline {
    agent any

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
                            aws ecs describe-task-definition --task-definition "$TASK_FAMILY" \
                                --query taskDefinition > current-task-definition.json

                            jq --arg IMAGE "$IMAGE_URI" '
                                del(.taskDefinitionArn, .revision, .status, .requiresAttributes,
                                    .compatibilities, .registeredAt, .registeredBy)
                                | .containerDefinitions[0].image = $IMAGE
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
                // service, then reports COMPLETED. Fail fast on FAILED or ALB health errors.
                sh '''
                    ALB_DNS=$(cat alb_dns.txt)
                    END=$(( $(date +%s) + BAKE_TIMEOUT_MIN * 60 ))
                    while [ "$(date +%s)" -lt "$END" ]; do
                        STATE=$(aws ecs describe-services --cluster "$ECS_CLUSTER" --services "$ECS_SERVICE" \
                            --query "services[0].deployments[?taskDefinition=='$NEW_TASK_DEF'] | [0].rolloutState" \
                            --output text)
                        echo "rollout=$STATE"
                        curl --fail --silent --show-error "http://$ALB_DNS/health" >/dev/null \
                            || { echo "ALB health check failed during bake"; exit 1; }
                        [ "$STATE" = "COMPLETED" ] && { echo "Bake complete"; exit 0; }
                        [ "$STATE" = "FAILED" ] && { echo "Rollout failed"; exit 1; }
                        sleep 30
                    done
                    echo "Bake period timed out"; exit 1
                '''
            }
        }
    }

    post {
        success {
            echo "Deployed ${env.IMAGE_URI} (${env.NEW_TASK_DEF}) successfully."
            // Add Slack / SNS / email notification here.
        }

        failure {
            script {
                echo "Pipeline failed."
                if (env.DEPLOY_STARTED == 'true' && env.PREVIOUS_TASK_DEF) {
                    echo "Rolling back to ${env.PREVIOUS_TASK_DEF}"
                    sh '''
                        aws ecs update-service \
                            --cluster "$ECS_CLUSTER" \
                            --service "$ECS_SERVICE" \
                            --task-definition "$PREVIOUS_TASK_DEF" >/dev/null
                    '''
                }
                // Add Slack / SNS / email notification here.
            }
        }

        always {
            sh 'docker logout "$ECR_REGISTRY" || true'
            sh 'docker image rm "$IMAGE_URI" || true'
            cleanWs()
        }
    }
}
