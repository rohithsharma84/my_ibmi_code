pipeline {
    agent any 
    
    environment {
        IBMI_HOST = 'pub400.com'
        IBMI_SSH_PORT = '2222'
    }
    
    stages {
        stage('Connect and test') {
            steps {
                withCredentials([usernamePassword(credentialsId: 'pub400-auth', 
                                                 usernameVariable: 'IBMI_USER', 
                                                 passwordVariable: 'IBMI_PASSWORD')]) {
                    nodejs('NodeJS_25') { 
                        sh """
                            # Install the tool if it doesn't exist
                            npm install -g @ibm/ibmi-ci
                            
                            # Run the command
                            ici --cl "DSPSYSVAL QDATE"
                        """
                    }
                }
            }
        }
    }
}
pipeline {
    agent any
    
    environment {
        IBMI_HOST   = 'pub400.com'
        IBMI_SSH_PORT = '2222'
        // Libraries as defined in your setup
        BUILD_LIB   = 'RSHARMA1'
        DEPLOY_LIB  = 'RSHARMA2'
        // IFS path for the pipeline build area
        REMOTE_PATH = '/home/RSHARMA/builds/my_ibmi_code'
    }

    stages {
        stage('Checkout') {
            steps {
                // Pulls from your GitHub repo
                checkout scm
            }
        }

        stage('Generate Build Manifest') {
            steps {
                script {
                    echo "Generating Makefile using Source Orbit..."
                    // 'so -m' generates a Makefile based on your source dependencies
                    sh 'so -m' 
                }
            }
        }

        stage('Sync & Build on IBM i') {
            steps {
                withCredentials([usernamePassword(credentialsId: 'pub400-auth', passwordVariable: 'IBMI_PASSWORD', usernameVariable: 'IBMI_USER')]) {
                    echo "Pushing code and running build in ${BUILD_LIB}..."
                    
                    // 1. Push source and Makefile to IFS
                    // 2. Execute gmake to compile into RSHARMA1
                    sh """
                    ici --host ${IBMI_HOST} --user ${IBMI_USER} --password ${IBMI_PASSWORD} \
                        --push . \
                        --rcwd ${REMOTE_PATH} \
                        --cmd "/QOpenSys/pkgs/bin/gmake BIN_LIB=${BUILD_LIB}"
                    """
                }
            }
        }

        stage('Deploy to Production') {
            steps {
                withCredentials([usernamePassword(credentialsId: 'pub400-auth', passwordVariable: 'IBMI_PASSWORD', usernameVariable: 'IBMI_USER')]) {
                    echo "Promoting objects from ${BUILD_LIB} to ${DEPLOY_LIB}..."
                    
                    // Move compiled programs/files to the target library
                    // This uses 'ici run' to execute a remote CL command
                    sh """
                    ici --host ${IBMI_HOST} --user ${IBMI_USER} --password ${IBMI_PASSWORD} \
                        --cmd "MOVOBJ OBJ(${BUILD_LIB}/*ALL) OBJTYPE(*ALL) TOLIB(${DEPLOY_LIB})"
                    """
                }
            }
        }
    }
    
    post {
        always {
            cleanWs()
        }
    }
}