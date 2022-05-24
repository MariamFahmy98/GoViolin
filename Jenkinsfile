pipeline {
  agent { label 'controller-node' }

  environment {
    DOCKER_USERNAME = credentials('docker-username')
    DOCKER_PASSWORD = credentials('docker-password')
  }

  stages {
    stage('Build Image') {
      steps {
        sh 'docker build -t $DOCKER_USERNAME/go-violin-app:latest .'
      }
    }

    stage('Login into dockerhub') {
      steps {
        sh 'docker login --username $DOCKER_USERNAME --password $DOCKER_PASSWORD'
      }
    }

    stage('Push to docker repository') {
      steps {
        sh 'docker push $DOCKER_USERNAME/go-violin-app:latest'
      }
    }

    stage('Deploy app to Kubernetes cluster') {
      steps {
        sh "kubectl apply --kubeconfig=${params.kubeConfig} -f kubernetes/deployment.yaml -f kubernetes/service.yaml"
      }
    }
  }

  post {
    always {
      sh 'docker logout'
    }

    failure {
      mail to: "mariamfahmy66@gmail.com",
      subject: "jenkins build:${currentBuild.currentResult}: ${env.JOB_NAME}",
      body: "${currentBuild.currentResult}: Job ${env.JOB_NAME}\nMore Info can be found here: ${env.BUILD_URL}"
    }

    success {
      mail to: "mariamfahmy66@gmail.com",
      subject: "jenkins build:${currentBuild.currentResult}: ${env.JOB_NAME}",
      body: "${currentBuild.currentResult}: Job ${env.JOB_NAME}\nMore Info can be found here: ${env.BUILD_URL}"
    }
  }
}