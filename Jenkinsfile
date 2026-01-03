pipeline {
    agent any

    environment {
        IBM_I_HOST = 'pub400.com'
        IBM_I_USER = 'RSHARMA'
        SSH_PORT   = '2222'
        SSH_OPTS   = '-o StrictHostKeyChecking=no'
    }

    stages {

        stage('Select Environment') {
            steps {
                script {
                    if (env.BRANCH_NAME.startsWith('feature/')) {
                        env.TARGET_LIB = 'RSHARMA1'
                        env.ENV_NAME   = 'DEV'
                    } else if (env.BRANCH_NAME == 'develop') {
                        env.TARGET_LIB = 'RSHARMAB'
                        env.ENV_NAME   = 'QA'
                    } else if (env.BRANCH_NAME == 'main') {
                        env.TARGET_LIB = 'RSHARMA2'
                        env.ENV_NAME   = 'PROD'
                    } else {
                        error "Unsupported branch: ${env.BRANCH_NAME}"
                    }
                }
            }
        }

        stage('Confirm Production Deploy') {
            when {
                branch 'main'
            }
            steps {
                input message: "Deploy to PROD library ${env.TARGET_LIB}?"
            }
        }

        stage('Sync Source to IBM i') {
            steps {
                sshagent(credentials: ['ibmi-ssh']) {
                    sh """
                    ssh -p ${SSH_PORT} ${SSH_OPTS} ${IBM_I_USER}@${IBM_I_HOST} "
                    rm -rf /home/${IBM_I_USER}/repo &&
                    mkdir -p /home/${IBM_I_USER}/repo
                    "
                    scp -P ${SSH_PORT} -r * ${IBM_I_USER}@${IBM_I_HOST}:/home/${IBM_I_USER}/repo
                    """
                }
            }
        }
        
        stage('Compile RPG') {
            steps {
                withCredentials([sshUserPrivateKey(
                    credentialsId: 'ibmi-ssh-key',
                    keyFileVariable: 'SSH_KEY',
                    usernameVariable: 'SSH_USER'
                )]) {
                    bat """
                    for %%f in (rpg\\*.rpgle) do (
                      ssh -i %SSH_KEY% -p 2222 %SSH_USER%@pub400.com ^
                      "system 'CRTBNDRPG PGM(${TARGET_LIB}/%%~nf) SRCSTMF(\\'/home/RSHARMA/jenkins/%%~nxf\\') DBGVIEW(*SOURCE)'"
                    )
                    """
                }
            }
        }

        stage('Compile CL') {
            steps {
                withCredentials([sshUserPrivateKey(
                    credentialsId: 'ibmi-ssh-key',
                    keyFileVariable: 'SSH_KEY',
                    usernameVariable: 'SSH_USER'
                )]) {
                    bat """
                    for %%f in (cl\\*.clle) do (
                      ssh -i %SSH_KEY% -p 2222 %SSH_USER%@pub400.com ^
                      "system 'CRTBNDCL PGM(${TARGET_LIB}/%%~nf) SRCSTMF(\\'/home/RSHARMA/jenkins/%%~nxf\\')'"
                    )
                    """
                }
            }
        }

        stage('Deploy DB Changes') {
            steps {
                withCredentials([sshUserPrivateKey(
                    credentialsId: 'ibmi-ssh-key',
                    keyFileVariable: 'SSH_KEY',
                    usernameVariable: 'SSH_USER'
                )]) {
                    bat """
                    for %%f in (db\\*.sql) do (
                      ssh -i %SSH_KEY% -p 2222 %SSH_USER%@pub400.com ^
                      "system 'RUNSQLSTM SRCSTMF(\\'/home/RSHARMA/jenkins/%%~nxf\\') COMMIT(*NONE)'"
                    )
                    """
                }
            }
        }
    }
    
    post {
        success {
            echo "Deployment to ${ENV_NAME} (${TARGET_LIB}) completed successfully."
        }
        failure {
            echo "Deployment failed."
        }
    }
}
