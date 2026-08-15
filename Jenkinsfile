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

        EC2_HOST       = '98.86.159.164' // or public IP
        EC2_USER       = 'ec2-user'
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

    stage('Deploy to EC2 Instance') {
        steps {
            withCredentials([
                file(credentialsId: 'ec2-ssh-key-file', variable: 'KEY_PATH'),
                aws(credentialsId: 'ECR-Access-ID', accessKeyVariable: 'AWS_ACCESS_KEY_ID', secretKeyVariable: 'AWS_SECRET_ACCESS_KEY')
            ]) {
                bat '''
                    "C:\\Program Files\\Git\\bin\\bash.exe" -c "ssh -i '%KEY_PATH%' -o StrictHostKeyChecking=no %EC2_USER%@%EC2_HOST% 'export AWS_ACCESS_KEY_ID=%AWS_ACCESS_KEY_ID% && export AWS_SECRET_ACCESS_KEY=%AWS_SECRET_ACCESS_KEY% && export AWS_DEFAULT_REGION=%AWS_REGION% && aws ecr get-login-password --region %AWS_REGION% | docker login --username AWS --password-stdin %ECR_URL% && docker stop %IMAGE_NAME% || true && docker rm %IMAGE_NAME% || true && docker pull %ECR_URL%/%IMAGE_NAME%:%IMAGE_TAG% && docker run -d --name %IMAGE_NAME% --restart unless-stopped -p 5000:5000 -e MONGO_URI=%MONGO_URI% %ECR_URL%/%IMAGE_NAME%:%IMAGE_TAG%'"
                '''
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
