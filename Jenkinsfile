pipeline {
    agent any

    environment {
        IBM_I_HOST = 'PUB400.com'
        IBM_I_USER = 'MYUSER'
        IBM_I_PORT = '2222'
    }

    stages {
        stage('Sync Source to IBM i') {
            steps {
                sshUserPrivateKey(
                    credentialsId: 'RSHARMA',
                    keyFileVariable: 'SSH_KEY',
                    usernameVariable: 'SSH_USER'
                ) {
                    sh """
                        echo "Syncing source to IBM i..."
                        scp -P $IBM_I_PORT ./local_source/* $SSH_USER@$IBM_I_HOST:/QSYS.LIB/MYLIB.LIB/
                    """
                }
            }
        }

        stage('Compile RPG') {
            steps {
                sshUserPrivateKey(
                    credentialsId: 'RSHARMA',
                    keyFileVariable: 'SSH_KEY',
                    usernameVariable: 'SSH_USER'
                ) {
                    sh """
                        echo "Compiling RPG..."
                        ssh -i $SSH_KEY -p $IBM_I_PORT $SSH_USER@$IBM_I_HOST 'CRTRPGMOD MODULE(MYLIB/MYMOD) SRCSTMF("/QSYS.LIB/MYLIB.LIB/HELLO.RPGLE")'
                        ssh -i $SSH_KEY -p $IBM_I_PORT $SSH_USER@$IBM_I_HOST 'CRTPGM PGM(MYLIB/MYPGM) MODULE(MYLIB/MYMOD)'
                    """
                }
            }
        }

        stage('Compile CL') {
            steps {
                sshUserPrivateKey(
                    credentialsId: 'RSHARMA',
                    keyFileVariable: 'SSH_KEY',
                    usernameVariable: 'SSH_USER'
                ) {
                    sh """
                        echo "Compiling CL..."
                        ssh -i $SSH_KEY -p $IBM_I_PORT $SSH_USER@$IBM_I_HOST 'CRTBNDCL PGM(MYLIB/MYCLPGM) SRCSTMF("/QSYS.LIB/MYLIB.LIB/HELLO.CLLE")'
                    """
                }
            }
        }

        stage('Deploy DB Changes') {
            steps {
                sshUserPrivateKey(
                    credentialsId: 'RSHARMA',
                    keyFileVariable: 'SSH_KEY',
                    usernameVariable: 'SSH_USER'
                ) {
                    sh """
                        echo "Deploying DB changes..."
                        ssh -i $SSH_KEY -p $IBM_I_PORT $SSH_USER@$IBM_I_HOST 'RUNSQL SQL("ALTER TABLE MYLIB/MYTABLE ADD COLUMN NEWCOL INT")'
                    """
                }
            }
        }
    } // <-- CLOSE stages

    post {
        success {
            echo 'Deployment succeeded!'
        }
        failure {
            echo 'Deployment failed.'
        }
    }
} // <-- CLOSE pipeline
