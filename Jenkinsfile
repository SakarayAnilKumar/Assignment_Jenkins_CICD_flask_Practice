pipeline {
    agent any

    environment {
        // AWS & ECR Settings
        AWS_ACCOUNT_ID = '316412036553'
        AWS_REGION     = 'us-east-1'
        IMAGE_NAME     = 'student-registration'
        IMAGE_TAG      = "${env.BUILD_NUMBER}"
        ECR_URL        = "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

        // EC2 Deployment Target Settings
        EC2_HOST       = '98.86.159.164'
        EC2_USER       = 'ec2-user' // Change to 'ubuntu' if using an Ubuntu EC2 instance
    }

    stages {
        stage('Checkout Code') {
            steps {
                checkout scm
            }
        }

        stage('Build Docker Image') {
            steps {
                script {
                    echo "Building Docker Image: ${ECR_URL}/${IMAGE_NAME}:${IMAGE_TAG}"
                    bat "docker build -t ${ECR_URL}/${IMAGE_NAME}:${IMAGE_TAG} ."
                    bat "docker tag ${ECR_URL}/${IMAGE_NAME}:${IMAGE_TAG} ${ECR_URL}/${IMAGE_NAME}:latest"
                }
            }
        }

        stage('Push Image to AWS ECR') {
            steps {
                // AWS Credentials setup in Jenkins (AWS Access Key ID + Secret Key)
                withCredentials([usernamePassword(credentialsId: 'aws-credentials-id', passwordVariable: 'AWS_SECRET_ACCESS_KEY', usernameVariable: 'AWS_ACCESS_KEY_ID')]) {
                    bat '''
                        "C:\\Program Files\\Git\\bin\\bash.exe" -c "aws ecr get-login-password --region %AWS_REGION% | docker login --username AWS --password-stdin %ECR_URL%"
                    '''
                    bat "docker push ${ECR_URL}/${IMAGE_NAME}:${IMAGE_TAG}"
                    bat "docker push ${ECR_URL}/${IMAGE_NAME}:latest"
                }
            }
        }

        stage('Deploy to EC2 Instance') {
            steps {
                // SSH Key setup in Jenkins as a Secret File credential
                withCredentials([file(credentialsId: 'ec2-ssh-key-file', variable: 'KEY_PATH')]) {
                    bat '''
                        "C:\\Program Files\\Git\\bin\\bash.exe" -c "ssh -i '%KEY_PATH%' -o StrictHostKeyChecking=no %EC2_USER%@%EC2_HOST% 'aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin %ECR_URL% && docker stop %IMAGE_NAME% || true && docker rm %IMAGE_NAME% || true && docker pull %ECR_URL%/%IMAGE_NAME%:%IMAGE_TAG% && docker run -d --name %IMAGE_NAME% --restart unless-stopped -p 80:80 %ECR_URL%/%IMAGE_NAME%:%IMAGE_TAG%'"
                    '''
                }
            }
        }
    }

    post {
        always {
            echo "Pipeline finished execution."
            // Cleanup local docker images on Jenkins agent to save disk space
            bat "docker rmi ${ECR_URL}/${IMAGE_NAME}:${IMAGE_TAG} || true"
            bat "docker rmi ${ECR_URL}/${IMAGE_NAME}:latest || true"
        }
        success {
            echo "Deployment to EC2 was successful! Access your app at: http://${env.EC2_HOST}"
        }
        failure {
            echo "Pipeline execution failed. Please inspect build logs."
        }
    }
}