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

        EC2_HOST       = '13.223.96.128' // or public IP
        EC2_USER       = 'ec2-user'
        STAGE_NAME   = 'Unknown Stage'
    }

    stages {
        stage('Checkout') {
            steps {
                env.STAGE_NAME = 'Checkout'
                checkout scm
            }
        }

        stage('Install Dependencies') {
            steps {
                env.STAGE_NAME = 'Install Dependencies'
                echo 'Installing dependencies...'
                sh 'python -m venv venv'
                sh 'source venv/Scripts/activate'
                sh 'python -m pip install --upgrade pip'
                sh 'pip install -r requirements.txt'
            }
        }

        stage('Test') {
            steps {
                env.STAGE_NAME = 'Test'
                echo 'Running tests...'
                sh 'pytest'
            }
        }

        stage('Build Docker Image') {
            steps {
                env.STAGE_NAME = 'Build Docker Image'
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
                env.STAGE_NAME = 'Authenticate & Push to ECR'
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
                env.STAGE_NAME = 'Deploy to EC2 Instance'
                withCredentials([
                    file(credentialsId: 'ec2-ssh-key-file', variable: 'KEY_PATH'),
                    aws(credentialsId: 'ECR-Access-ID', accessKeyVariable: 'AWS_ACCESS_KEY_ID', secretKeyVariable: 'AWS_SECRET_ACCESS_KEY'),
                    string(credentialsId: 'MONGO_URI', variable: 'MONGO_URI')
                ]) {
                    bat '''
                        "C:\\Program Files\\Git\\bin\\bash.exe" -c "ssh -i '%KEY_PATH%' -o StrictHostKeyChecking=no %EC2_USER%@%EC2_HOST% 'export AWS_ACCESS_KEY_ID=%AWS_ACCESS_KEY_ID% && export AWS_SECRET_ACCESS_KEY=%AWS_SECRET_ACCESS_KEY% && export AWS_DEFAULT_REGION=%AWS_REGION% && aws ecr get-login-password --region %AWS_REGION% | docker login --username AWS --password-stdin %ECR_URL% && docker stop %IMAGE_NAME% || true && docker rm %IMAGE_NAME% || true && docker pull %ECR_URL%/%IMAGE_NAME%:%IMAGE_TAG% && docker run -d --name %IMAGE_NAME% --restart unless-stopped -p 5000:5000 -e MONGO_URI=\\"%MONGO_URI%\\" %ECR_URL%/%IMAGE_NAME%:%IMAGE_TAG% && sleep 3 && docker ps | grep %IMAGE_NAME%'"
                    '''
                }
            }
        }
        stage('Validate Application Health') {
            steps {
                env.STAGE_NAME = 'Validate Application Health'
                powershell '''
                    Start-Sleep -Seconds 5
                    $url = "http://${env:EC2_HOST}:5000/health"
                    Write-Host "===> Checking health endpoint: $url"

                    try {
                        $response = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 10
                        $statusCode = $response.StatusCode
                    } catch {
                        if ($_.Exception.Response) {
                            $statusCode = [int]$_.Exception.Response.StatusCode
                        } else {
                            $statusCode = 0
                        }
                    }

                    Write-Host "===> Received HTTP Status Code: $statusCode"

                    if ($statusCode -eq 200) {
                        Write-Host "===> [SUCCESS] Health check passed! HTTP 200 OK."
                    } else {
                        Write-Error "===> [ERROR] Health check failed with status code: $statusCode"
                        exit 1
                    }
                '''
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
                body: """
                    <h2>Build Status: SUCCESS</h2>
                    <p>Job <b>${env.JOB_NAME}</b> [Build #${env.BUILD_NUMBER}] completed successfully.</p>
                    <hr/>
                    <p><b>Deployment Details:</b></p>
                    <ul>
                        <li><b>Commit SHA:</b> ${env.GIT_COMMIT ? env.GIT_COMMIT : 'N/A'}</li>
                        <li><b>Image Tag:</b> ${env.ECR_URL}/${env.IMAGE_NAME}:${env.IMAGE_TAG}</li>
                    </ul>
                    <hr/>
                    <p>Check build details at: <a href='${env.BUILD_URL}'>${env.BUILD_URL}</a></p>
                """,
                to: 'anilirctc26@gmail.com',
                mimeType: 'text/html'
            )
        }

        failure {
            echo 'Pipeline execution failed'
            emailext (
                subject: "FAILED: Job '${env.JOB_NAME}' [Build #${env.BUILD_NUMBER}]",
                body: """
                    <h2>Build Status: FAILED</h2>
                    <p>Job <b>${env.JOB_NAME}</b> [Build #${env.BUILD_NUMBER}] failed to complete.</p>
                    <hr/>
                    <p><b>Failure Details:</b></p>
                    <ul>
                        <li><b>Failed Stage:</b> <span style='color:red;'>${env.STAGE_NAME ? env.STAGE_NAME : 'Unknown Stage'}</span></li>
                        <li><b>Commit SHA:</b> ${env.GIT_COMMIT ? env.GIT_COMMIT : 'N/A'}</li>
                        <li><b>Image Tag:</b> ${env.ECR_URL}/${env.IMAGE_NAME}:${env.IMAGE_TAG}</li>
                    </ul>
                    <hr/>
                    <p>Check console output at: <a href='${env.BUILD_URL}console'>${env.BUILD_URL}console</a></p>
                """,
                to: 'anilirctc26@gmail.com',
                mimeType: 'text/html'
            )
        }
    }
}
