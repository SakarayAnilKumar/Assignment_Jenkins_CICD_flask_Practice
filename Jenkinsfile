pipeline {
    agent any

environment {
        // Fetch secret from Jenkins credentials store using the ID 'MONGO_URI'
        MONGO_URI = credentials('MONGO_URI') 
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
                echo 'Building Docker image...'
                sh 'docker build -t student-registration:latest .'
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
