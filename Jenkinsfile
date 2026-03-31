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
                nodejs('NodeJS_25') { 
                    withCredentials([usernamePassword(credentialsId: 'pub400-auth', passwordVariable: 'IBMI_PASSWORD', usernameVariable: 'IBMI_USER')]) {
                        sh """
                            # 1. Ensure tools are available in this node session
                            npm install -g @ibm/sourceorbit @ibm/ibmi-ci
                            
                            # 2. Generate the Makefile locally using Source Orbit
                            # This maps dependencies across your QRPGLESRC, QCLSRC, etc.
                            so -m
                            
                            # 3. Push workspace (source + Makefile) to IFS and compile
                            # We use gmake on pub400 to execute the build into RSHARMA1
                            ici --host ${IBMI_HOST} --port ${IBMI_SSH_PORT} \
                                --user ${IBMI_USER} --password ${IBMI_PASSWORD} \
                                --push . \
                                --rcwd ${REMOTE_PATH} \
                                --cmd "/QOpenSys/pkgs/bin/gmake BIN_LIB=${BUILD_LIB}"
                        """
                    }
                }
            }
        }

        stage('Deploy to Production') {
            steps {
                nodejs('NodeJS_25') {
                    withCredentials([usernamePassword(credentialsId: 'pub400-auth', passwordVariable: 'IBMI_PASSWORD', usernameVariable: 'IBMI_USER')]) {
                        echo "Promoting objects from ${BUILD_LIB} to ${DEPLOY_LIB}..."
                        
                        // Moves all successfully compiled objects to the production library
                        sh """
                            ici --host ${IBMI_HOST} --port ${IBMI_SSH_PORT} \
                                --user ${IBMI_USER} --password ${IBMI_PASSWORD} \
                                --cmd "MOVOBJ OBJ(${BUILD_LIB}/*ALL) OBJTYPE(*ALL) TOLIB(${DEPLOY_LIB})"
                        """
                    }
                }
            }
        }
    }

    post {
        success {
            echo 'Build and Deployment to RSHARMA2 successful.'
        }
        failure {
            echo 'Pipeline failed. Check the Jenkins console and pub400 job logs.'
        }
        always {
            // Clean the Jenkins workspace to keep the agent tidy
            cleanWs()
        }
    }
}