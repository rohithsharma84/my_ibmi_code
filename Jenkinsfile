pipeline {
    agent any

    environment {
        IBM_I_HOST = 'pub400.com'
        IBM_I_USER = 'RSHARMA'
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
                    ssh ${IBM_I_USER}@${IBM_I_HOST} "
                    rm -rf /home/${IBM_I_USER}/repo &&
                    mkdir -p /home/${IBM_I_USER}/repo
                    "
                    scp -r * ${IBM_I_USER}@${IBM_I_HOST}:/home/${IBM_I_USER}/repo
                    """
                }
            }
        }
        
        stage('Compile RPG') {
            steps {
                sshagent(credentials: ['ibmi-ssh']) {
                    sh """
                    ssh ${IBM_I_USER}@${IBM_I_HOST} "
                    for f in rpg/*.rpgle; do
                      PGM=\$(basename \$f .rpgle)
                      CRTBNDRPG PGM(${TARGET_LIB}/\$PGM) SRCSTMF('/home/${IBM_I_USER}/repo/\$f')
                    done
                    "
                    """
                }
            }
        }

        stage('Compile CL') {
            steps {
                sshagent(credentials: ['ibmi-ssh']) {
                    sh """
                    ssh ${IBM_I_USER}@${IBM_I_HOST} "
                    for f in cl/*.clle; do
                      PGM=\$(basename \$f .clle)
                      CRTCLPGM PGM(${TARGET_LIB}/\$PGM) SRCSTMF('/home/${IBM_I_USER}/repo/\$f')
                    done
                    "
                    """
                }
            }
        }

        stage('Deploy DB Changes') {
            steps {
                sshagent(credentials: ['ibmi-ssh']) {
                    sh """
                    ssh ${IBM_I_USER}@${IBM_I_HOST} "
                    for f in db/*.sql; do
                      RUNSQLSTM SRCSTMF('/home/${IBM_I_USER}/repo/\$f')
                    done
                    "
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
