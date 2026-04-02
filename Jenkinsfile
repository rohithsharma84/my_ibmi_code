pipeline {
    agent any

    environment {
        IBMI_HOST   = 'pub400.com'
        IBMI_SSH_PORT = '2222'
        BUILD_LIB   = 'RSHARMA1'
        DEPLOY_LIB  = 'RSHARMA2'
        REMOTE_PATH = '/home/RSHARMA/builds/my_ibmi_code'
    }

    stages {
        stage('Checkout') {
            steps {
                // Pulls code from your GitHub repository
                checkout scm
            }
        }

        stage('Build & Sync') {
            steps {
                // Uses the NodeJS installation defined in Jenkins Global Tool Configuration
                script {
                    def branchName = env.BRANCH_NAME ?: env.GIT_BRANCH ?: 'main'
                    echo "Using branch: ${branchName}"
                }
                nodejs('NodeJS_25') { 
                    withCredentials([usernamePassword(credentialsId: 'pub400-auth', passwordVariable: 'IBMI_PASSWORD', usernameVariable: 'IBMI_USER')]) {
                        sh """
                            npm install -g @ibm/sourceorbit @ibm/ibmi-ci
                            
                            echo "--- Generating makefile ---"
                            so -bf make --verbose
                            
                            ici \
                                --cmd "mkdir -p '${REMOTE_PATH}/${branchName}'" \
                                --rcwd "${REMOTE_PATH}/${branchName}" \
                                --push "." \
                                --cmd "/QOpenSys/pkgs/bin/gmake BIN_LIB=${BUILD_LIB}"
                        """
                    }
                }
            }
        }

    }

    post {
        success {
            echo '--- Build successful ---'
        }
        failure {
            echo 'Pipeline failed. Check the Jenkins console output for details.'
        }
        always {
            // Clean the Jenkins workspace to keep the agent tidy
            cleanWs()
        }
    }
}