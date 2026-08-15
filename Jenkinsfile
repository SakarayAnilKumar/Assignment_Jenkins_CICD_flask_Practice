pipeline {
    agent any

environment {
        // Fetch secret from Jenkins credentials store using the ID 'MONGO_URI'
        MONGO_URI = credentials('MONGO_URI') 
        AWS_ACCOUNT_ID = '316412036553'
        AWS_REGION     = 'us-east-1'
        IMAGE_NAME     = 'student-registration'
        IMAGE_TAG      = "${env.BUILD_NUMBER}"
        ECR_URL        = "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        stage('Install Dependencies') {
            steps {
                echo 'Installing dependencies...'
                sh 'python -m venv venv'
                sh 'source venv/Scripts/activate'
                sh 'python -m pip install --upgrade pip'
                sh 'pip install -r requirements.txt'
            }
        }

        stage('Test') {
            steps {
                echo 'Running tests...'
                sh 'pytest'
            }
        }

        stage('Build Docker Image') {
            steps {
                script {
                    echo "Building ${IMAGE_NAME}:${IMAGE_TAG}..."
                    sh "docker build -t ${IMAGE_NAME}:${IMAGE_TAG} ."
                    sh "docker tag ${IMAGE_NAME}:${IMAGE_TAG} ${ECR_URL}/${IMAGE_NAME}:${IMAGE_TAG}"
                    sh "docker tag ${IMAGE_NAME}:${IMAGE_TAG} ${ECR_URL}/${IMAGE_NAME}:latest"
                }
            }
        }
        stage('Authenticate & Push to ECR') {
                    steps {
                        withCredentials([[
                            $class: 'AmazonWebServicesCredentialsBinding',
                            credentialsId: 'ECR-Access-ID'
                        ]]) {
                            script {
                                echo "Authenticating to ECR..."
                                sh "aws ecr get-login-password --region ${AWS_REGION} | docker login --username AWS --password-stdin ${ECR_URL}"
                                
                                echo "Pushing image to ECR..."
                                sh "docker push ${ECR_URL}/${IMAGE_NAME}:${IMAGE_TAG}"
                                sh "docker push ${ECR_URL}/${IMAGE_NAME}:latest"
                            }
                        }
                    }
                }

        stage('Deploy to EC2 via SSH') {
            steps {
                sshagent(['ec2-ssh-key']) {
                    sh """
                        ssh -o StrictHostKeyChecking=no ${EC2_USER}@${EC2_HOST} '
                            # 1. Login to ECR
                            aws ecr get-login-password --region ${AWS_REGION} | docker login --username AWS --password-stdin ${ECR_URL}

                            # 2. Stop and remove existing container (if running)
                            docker stop ${IMAGE_NAME} || true
                            docker rm ${IMAGE_NAME} || true

                            # 3. Pull latest image
                            docker pull ${ECR_URL}/${IMAGE_NAME}:${IMAGE_TAG}

                            # 4. Run new container
                            docker run -d \\
                              --name ${IMAGE_NAME} \\
                              --restart unless-stopped \\
                              -p 80:80 \\
                              ${ECR_URL}/${IMAGE_NAME}:${IMAGE_TAG}
                            docker image prune -f
                        '
                    """
                }
            }
        }
    }

    post {
        always {
            echo 'Pipeline execution completed'
        }
    success {
        echo 'Pipeline executed successfully'   
            emailext (
                subject: "SUCCESSFUL: Job '${env.JOB_NAME}' [Build #${env.BUILD_NUMBER}]",
                body: """<p>SUCCESSFUL: Job '${env.JOB_NAME}' [Build #${env.BUILD_NUMBER}]</p>
                         <p>Check build details at: <a href='${env.BUILD_URL}'>${env.BUILD_URL}</a></p>""",
                to: 'anilirctc26@gmail.com',
                mimeType: 'text/html'
            )
        }

        failure {
            echo 'Pipeline execution failed'
            emailext (
                subject: "FAILED: Job '${env.JOB_NAME}' [Build #${env.BUILD_NUMBER}]",
                body: """<p>FAILED: Job '${env.JOB_NAME}' [Build #${env.BUILD_NUMBER}]</p>
                         <p>Check console output at: <a href='${env.BUILD_URL}console'>${env.BUILD_URL}console</a></p>""",
                to: 'anilirctc26@gmail.com',
                mimeType: 'text/html'
            )
        }
    }
}
